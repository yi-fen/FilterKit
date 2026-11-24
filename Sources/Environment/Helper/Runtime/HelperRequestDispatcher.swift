import Foundation

/// Central Helper request gate. It owns request freshness, session binding, replay protection,
/// payload decoding, release checks, and request-level audit decisions. P1-25 deliberately keeps
/// operation execution disabled; this dispatcher is the single future insertion point for the
/// verified ownership/deployment pipeline.
final class HelperRequestDispatcher {
    static let executionReleased = false

    enum RejectionCode: String, Codable {
        case invalidSession = "invalid_session"
        case staleRequest = "stale_request"
        case replayedRequest = "replayed_request"
        case malformedOperation = "malformed_operation"
        case malformedBatch = "malformed_batch"
        case executionDisabled = "execution_disabled"
        case dispatchNotConfigured = "dispatch_not_configured"
        case authorizationFailed = "authorization_failed"
        case deploymentFailed = "deployment_failed"
        case auditUnavailable = "audit_unavailable"
        case maintenanceRecoveryNotReleased = "maintenance_recovery_not_released"
        case recoveryRequired = "recovery_required"
        case invalidTransactionJournal = "invalid_transaction_journal"
        case messageNotAllowed = "message_not_allowed"
    }

    struct Rejection: Codable, Equatable {
        let code: RejectionCode
        let message: String
    }

    private let manifest: HelperDeploymentManifest
    private let audit: HelperAuditSink
    private let replayGuard: HelperRequestReplayGuard
    private let clockSkewLimit: TimeInterval
    private let deploymentPipeline: HelperDeploymentPipeline?
    private let pluginDirectory: String?

    init(manifest: HelperDeploymentManifest,
         audit: HelperAuditSink,
         replayGuard: HelperRequestReplayGuard = HelperRequestReplayGuard(),
         clockSkewLimit: TimeInterval = 120,
         deploymentPipeline: HelperDeploymentPipeline? = nil,
         pluginDirectory: String? = nil) {
        self.manifest = manifest
        self.audit = audit
        self.replayGuard = replayGuard
        self.clockSkewLimit = max(1, clockSkewLimit)
        self.deploymentPipeline = deploymentPipeline
        self.pluginDirectory = pluginDirectory
    }

    func dispatch(_ envelope: HelperIPCEnvelope,
                  context: HelperAuthenticatedPeerContext,
                  now: Date = Date()) -> HelperIPCEnvelope {
        guard envelope.protocolVersion == HelperIPCEnvelope.currentVersion,
              let nonce = envelope.nonce, nonce == context.sessionNonce,
              context.peer.uid == context.identity.uid,
              context.peer.gid == context.identity.gid,
              context.peer.pid == context.identity.pid,
              context.identity.pid > 0,
              abs(now.timeIntervalSince(context.authenticatedAt)) <= clockSkewLimit else {
            return reject(envelope, code: .invalidSession, operation: nil, peer: context.identity)
        }
        guard abs(now.timeIntervalSince(envelope.createdAt)) <= clockSkewLimit else {
            return reject(envelope, code: .staleRequest, operation: nil, peer: context.identity)
        }
        guard replayGuard.accept(envelope.requestID, now: now) else {
            return reject(envelope, code: .replayedRequest, operation: nil, peer: context.identity)
        }

        switch envelope.messageType {
        case .healthRequest:
            do {
                try audit.append(HelperAuditRecord(requestID: envelope.requestID, peer: context.identity,
                    outcome: .accepted, reasonCode: "health_check"))
            } catch {
                return reject(envelope, code: .auditUnavailable, operation: nil, peer: context.identity)
            }
            let status = recoveryStatus()
            let response = HelperStatusResponse(helperReachable: true, recoveryStatus: status,
                                                checkedAt: now, protocolVersion: HelperIPCEnvelope.currentVersion)
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            return HelperIPCEnvelope(messageType: .healthResponse, requestID: envelope.requestID,
                                     createdAt: now, nonce: context.sessionNonce,
                                     payload: try? encoder.encode(response))

        case .maintenanceRecoveryRequest:
            guard let payload = envelope.payload,
                  let request = Self.decodeMaintenanceRequest(payload),
                  request.requestNonce != UUID(uuidString: "00000000-0000-0000-0000-000000000000"),
                  abs(request.requestedAt.timeIntervalSince(envelope.createdAt)) <= 5,
                  abs(now.timeIntervalSince(request.requestedAt)) <= clockSkewLimit else {
                return reject(envelope, code: .malformedOperation, operation: nil, peer: context.identity)
            }
            let currentStatus = recoveryStatus()
            let result: HelperMaintenanceResult
            switch request.action {
            case .inspect:
                result = .inspected
            case .reconcileThreeFileTransaction:
                // P1-32 exposes the authenticated maintenance protocol but deliberately does not
                // execute recovery mutations until Darwin/device validation and release approval.
                result = .recoveryNotReleased
            }
            do {
                try audit.append(HelperAuditRecord(requestID: envelope.requestID, peer: context.identity,
                    outcome: request.action == .inspect ? .accepted : .rejected,
                    reasonCode: request.action == .inspect ? "maintenance_inspect" : RejectionCode.maintenanceRecoveryNotReleased.rawValue))
            } catch {
                return reject(envelope, code: .auditUnavailable, operation: nil, peer: context.identity)
            }
            let response = HelperMaintenanceRecoveryResponse(result: result, recoveryStatus: currentStatus,
                                                             completedAt: now)
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            return HelperIPCEnvelope(messageType: .maintenanceRecoveryResponse, requestID: envelope.requestID,
                                     createdAt: now, nonce: context.sessionNonce,
                                     payload: try? encoder.encode(response))

        case .deploymentBatchRequest:
            guard let payload = envelope.payload,
                  let batch = Self.decodeBatch(payload),
                  batch.batchID == envelope.requestID,
                  abs(batch.createdAt.timeIntervalSince(envelope.createdAt)) <= 5,
                  (try? batch.validate(now: now, clockSkewLimit: clockSkewLimit)) != nil else {
                return reject(envelope, code: .malformedBatch, operation: nil, peer: context.identity)
            }
            // Protect both the batch envelope ID and each operation ID. A caller cannot evade
            // replay protection by wrapping previously seen operations in a fresh batch UUID.
            guard batch.operations.allSatisfy({ replayGuard.accept($0.requestID, now: now) }) else {
                return reject(envelope, code: .replayedRequest, operation: nil, peer: context.identity)
            }
            switch recoveryStatus() {
            case .clean: break
            case .legacyRecoveryRequired, .threeFileRecoveryRequired, .bothRecoveryRequired:
                return reject(envelope, code: .recoveryRequired, operation: nil, peer: context.identity)
            case .invalidJournal, .unavailable:
                return reject(envelope, code: .invalidTransactionJournal, operation: nil, peer: context.identity)
            }
            guard Self.executionReleased, manifest.executionEnabled else {
                return reject(envelope, code: .executionDisabled, operation: nil, peer: context.identity)
            }
            guard let deploymentPipeline else {
                return reject(envelope, code: .dispatchNotConfigured, operation: nil, peer: context.identity)
            }
            do {
                let receipt = try deploymentPipeline.execute(batch, context: context, now: now)
                let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
                let payload = try encoder.encode(receipt)
                try audit.append(HelperAuditRecord(requestID: envelope.requestID, peer: context.identity,
                    outcome: .accepted, reasonCode: "deployment_batch_committed"))
                return HelperIPCEnvelope(messageType: .deploymentBatchReceipt, requestID: envelope.requestID,
                    createdAt: now, nonce: context.sessionNonce, payload: payload)
            } catch HelperDeploymentPipeline.PipelineError.authorizationFailed {
                return reject(envelope, code: .authorizationFailed, operation: nil, peer: context.identity)
            } catch HelperDeploymentPipeline.PipelineError.invalidBatch,
                    HelperDeploymentPipeline.PipelineError.proofMismatch,
                    HelperDeploymentPipeline.PipelineError.planMismatch {
                return reject(envelope, code: .malformedBatch, operation: nil, peer: context.identity)
            } catch {
                return reject(envelope, code: .deploymentFailed, operation: nil, peer: context.identity)
            }

        case .operationRequest:
            guard let payload = envelope.payload,
                  let request = Self.decodeOperation(payload),
                  request.requestID == envelope.requestID,
                  abs(request.createdAt.timeIntervalSince(envelope.createdAt)) <= 5,
                  abs(now.timeIntervalSince(request.createdAt)) <= clockSkewLimit,
                  request.pluginID != UUID(uuidString: "00000000-0000-0000-0000-000000000000"),
                  Self.validOperationShape(request) else {
                return reject(envelope, code: .malformedOperation, operation: nil, peer: context.identity)
            }

            // The global release gate is intentionally false. Even a mistakenly enabled
            // on-disk manifest cannot activate deployment until a separately reviewed release.
            switch recoveryStatus() {
            case .clean: break
            case .legacyRecoveryRequired, .threeFileRecoveryRequired, .bothRecoveryRequired:
                return reject(envelope, code: .recoveryRequired, operation: request.operation, peer: context.identity)
            case .invalidJournal, .unavailable:
                return reject(envelope, code: .invalidTransactionJournal, operation: request.operation, peer: context.identity)
            }
            guard Self.executionReleased, manifest.executionEnabled else {
                return reject(envelope, code: .executionDisabled, operation: request.operation, peer: context.identity)
            }
            // P1-25 wires the dispatch boundary, not the privileged executor. This branch remains
            // fail-closed even if a test or edited manifest flips the configuration bit.
            return reject(envelope, code: .dispatchNotConfigured, operation: request.operation, peer: context.identity)

        default:
            return reject(envelope, code: .messageNotAllowed, operation: nil, peer: context.identity)
        }
    }

    private func reject(_ envelope: HelperIPCEnvelope, code: RejectionCode,
                        operation: HelperOperation?, peer: HelperPeerIdentity) -> HelperIPCEnvelope {
        let record = HelperAuditRecord(requestID: envelope.requestID, operation: operation, peer: peer,
            outcome: .rejected, reasonCode: code.rawValue)
        do { try audit.append(record) } catch {
            // Never turn an audit failure into permission to continue. The response still reports
            // the original denial; the missing audit event is detectable through service logs.
        }
        let payload = try? JSONEncoder().encode(Rejection(code: code, message: code.rawValue))
        return HelperIPCEnvelope(messageType: .rejected, requestID: envelope.requestID,
                                 payload: payload)
    }

    private func recoveryStatus() -> HelperRecoveryStatus {
        let detail: HelperStartupRecoveryCheck.Detail
        guard let pluginDirectory else { return .unavailable }
        detail = HelperStartupRecoveryCheck().inspectDetailed(pluginDirectory: pluginDirectory)
        switch detail {
        case .clean: return .clean
        case .legacyRecoveryRequired: return .legacyRecoveryRequired
        case .threeFileRecoveryRequired: return .threeFileRecoveryRequired
        case .bothRecoveryRequired: return .bothRecoveryRequired
        case .invalidJournal: return .invalidJournal
        }
    }

    private static func decodeMaintenanceRequest(_ data: Data) -> HelperMaintenanceRecoveryRequest? {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(HelperMaintenanceRecoveryRequest.self, from: data)
    }

    private static func decodeBatch(_ data: Data) -> HelperDeploymentBatchRequest? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(HelperDeploymentBatchRequest.self, from: data)
    }

    private static func decodeOperation(_ data: Data) -> HelperOperationRequest? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(HelperOperationRequest.self, from: data)
    }

    private static func validOperationShape(_ request: HelperOperationRequest) -> Bool {
        guard HelperPolicy.isSafeLeafName(request.targetFileName) else { return false }
        switch request.operation {
        case .installDylib:
            return request.targetFileName.lowercased().hasSuffix(".dylib") &&
                request.stagingRelativePath.map(HelperPolicy.isSafeRelativePath) == true &&
                request.expectedSHA256.map(HelperPolicy.isValidHash) == true
        case .replaceFilterPlist:
            return request.targetFileName.lowercased().hasSuffix(".plist") &&
                request.stagingRelativePath.map(HelperPolicy.isSafeRelativePath) == true &&
                request.expectedSHA256.map(HelperPolicy.isValidHash) == true
        case .removeUnmanagedDylib:
            // Removal stays unavailable until a distinct ownership-bound delete authorization exists.
            return false
        }
    }
}
