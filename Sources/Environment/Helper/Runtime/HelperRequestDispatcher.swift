import Foundation

/// Central Helper request gate. It owns request freshness, session binding, replay protection,
/// payload decoding, release checks, and request-level audit decisions. P1-25 deliberately keeps
/// operation execution disabled; this dispatcher is the single future insertion point for the
/// verified ownership/deployment pipeline.
final class HelperRequestDispatcher {
    static let executionReleased = false
    /// Association writes remain independently locked pending RootHide device validation.
    static let pluginAssociationCommitReleased = false

    enum RejectionCode: String, Codable {
        case invalidSession = "invalid_session"
        case staleRequest = "stale_request"
        case replayedRequest = "replayed_request"
        case deploymentBatchInProgress = "deployment_batch_in_progress"
        case deploymentBatchOutcomeUnknown = "deployment_batch_outcome_unknown"
        case deploymentBatchRolledBack = "deployment_batch_rolled_back"
        case deploymentBatchConflict = "deployment_batch_id_conflict"
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
        case malformedPluginMutation = "malformed_plugin_mutation"
        case pluginMutationAuthorizationFailed = "plugin_mutation_authorization_failed"
        case pluginMutationRecoveryRequired = "plugin_mutation_recovery_required"
        case pluginMutationAuditUnavailable = "plugin_mutation_audit_unavailable"
        case malformedIdentityAttestation = "malformed_identity_attestation"
        case malformedAppPluginActivation = "malformed_app_plugin_activation"
        case appPluginActivationAuthorizationFailed = "app_plugin_activation_authorization_failed"
        case identityAttestationUnavailable = "identity_attestation_unavailable"
    }

    struct Rejection: Codable, Equatable {
        let code: RejectionCode
        let message: String
    }

    private let manifest: HelperDeploymentManifest
    private let audit: HelperAuditSink
    private let replayGuard: HelperRequestReplayGuard
    private let deploymentIdempotencyLedger: HelperDeploymentIdempotencyLedger
    private let deploymentLedgerStore: HelperDeploymentDurableLedgerStore?
    private let clockSkewLimit: TimeInterval
    private let deploymentPipeline: HelperDeploymentPipeline?
    private let pluginDirectory: String?
    private let pluginFilterMutationAuthorizer: HelperPluginFilterMutationAuthorizer?
    private let pluginAssociationTransaction: HelperPluginFilterConfigurationTransaction?
    private let pluginIdentityAttestor: HelperPluginIdentityAttestor?
    /// Test-injectable only; production construction leaves activation writes disabled.
    private let activationCommitExecutionEnabled: Bool

    init(manifest: HelperDeploymentManifest,
         audit: HelperAuditSink,
         replayGuard: HelperRequestReplayGuard = HelperRequestReplayGuard(),
         deploymentIdempotencyLedger: HelperDeploymentIdempotencyLedger = HelperDeploymentIdempotencyLedger(),
         deploymentLedgerStore: HelperDeploymentDurableLedgerStore? = nil,
         clockSkewLimit: TimeInterval = 120,
         deploymentPipeline: HelperDeploymentPipeline? = nil,
         pluginDirectory: String? = nil,
         pluginFilterMutationAuthorizer: HelperPluginFilterMutationAuthorizer? = nil,
         pluginAssociationTransaction: HelperPluginFilterConfigurationTransaction? = nil,
         pluginIdentityAttestor: HelperPluginIdentityAttestor? = nil,
         activationCommitExecutionEnabled: Bool = false) {
        self.manifest = manifest
        self.audit = audit
        self.replayGuard = replayGuard
        self.deploymentIdempotencyLedger = deploymentIdempotencyLedger
        self.deploymentLedgerStore = deploymentLedgerStore
        self.clockSkewLimit = max(1, clockSkewLimit)
        self.deploymentPipeline = deploymentPipeline
        self.pluginDirectory = pluginDirectory
        self.pluginFilterMutationAuthorizer = pluginFilterMutationAuthorizer
        self.pluginAssociationTransaction = pluginAssociationTransaction
        self.pluginIdentityAttestor = pluginIdentityAttestor
        self.activationCommitExecutionEnabled = activationCommitExecutionEnabled
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
        if envelope.messageType != .deploymentBatchRequest {
            guard replayGuard.accept(envelope.requestID, now: now) else {
                return reject(envelope, code: .replayedRequest, operation: nil, peer: context.identity)
            }
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
                  request.requestNonce == envelope.requestID,
                  request.requestNonce != UUID(uuidString: "00000000-0000-0000-0000-000000000000"),
                  abs(request.requestedAt.timeIntervalSince(envelope.createdAt)) <= 5,
                  abs(now.timeIntervalSince(request.requestedAt)) <= clockSkewLimit else {
                return reject(envelope, code: .malformedOperation, operation: nil, peer: context.identity)
            }
            let currentStatus = recoveryStatus()
            let result: HelperMaintenanceResult
            var boundTransactionID: UUID? = nil
            switch request.action {
            case .inspect:
                result = .inspected
            case .reconcileThreeFileTransaction:
                guard request.operatorConfirmed,
                      let transactionID = request.transactionID,
                      transactionID != UUID(uuidString: "00000000-0000-0000-0000-000000000000") else {
                    return reject(envelope, code: .malformedOperation, operation: nil, peer: context.identity)
                }
                do {
                    _ = try HelperRecoveryAuthorization.authorize(context: context,
                        transactionID: transactionID, requestNonce: request.requestNonce,
                        operatorConfirmed: request.operatorConfirmed, now: now,
                        clockSkewLimit: clockSkewLimit)
                    boundTransactionID = transactionID
                    // Authorization is integrated end-to-end, but recovery mutation remains
                    // disabled pending Darwin/Xcode and RootHide device validation.
                    result = .recoveryNotReleased
                } catch {
                    return reject(envelope, code: .malformedOperation, operation: nil, peer: context.identity)
                }
            }
            do {
                try audit.append(HelperAuditRecord(requestID: envelope.requestID, peer: context.identity,
                    outcome: request.action == .inspect ? .accepted : .rejected,
                    reasonCode: request.action == .inspect ? "maintenance_inspect" :
                        (boundTransactionID == nil ? "maintenance_authorization_rejected" : RejectionCode.maintenanceRecoveryNotReleased.rawValue)))
            } catch {
                return reject(envelope, code: .auditUnavailable, operation: nil, peer: context.identity)
            }
            let response = HelperMaintenanceRecoveryResponse(result: result, recoveryStatus: currentStatus,
                completedAt: now, transactionID: boundTransactionID)
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            return HelperIPCEnvelope(messageType: .maintenanceRecoveryResponse, requestID: envelope.requestID,
                                     createdAt: now, nonce: context.sessionNonce,
                                     payload: try? encoder.encode(response))

        case .pluginIdentityAttestationRequest:
            guard let payload = envelope.payload,
                  let request = Self.decodePluginIdentityAttestation(payload),
                  request.requestID == envelope.requestID,
                  abs(request.createdAt.timeIntervalSince(envelope.createdAt)) <= 5,
                  request.validate(now: now, clockSkewLimit: clockSkewLimit) else {
                return reject(envelope, code: .malformedIdentityAttestation, operation: nil, peer: context.identity)
            }
            guard recoveryStatus() == .clean,
                  let attestor = pluginIdentityAttestor else {
                return reject(envelope, code: .identityAttestationUnavailable, operation: nil, peer: context.identity)
            }
            let attestation = attestor.attest(request, now: now)
            do {
                try audit.append(HelperAuditRecord(requestID: envelope.requestID, peer: context.identity,
                    outcome: attestation.isVerified ? .accepted : .rejected,
                    reasonCode: "plugin_identity_attestation.\(attestation.reasonCode ?? "unknown")"))
            } catch {
                return reject(envelope, code: .auditUnavailable, operation: nil, peer: context.identity)
            }
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            guard let data = try? encoder.encode(attestation) else {
                return reject(envelope, code: .malformedIdentityAttestation, operation: nil, peer: context.identity)
            }
            return HelperIPCEnvelope(messageType: .pluginIdentityAttestationResponse,
                requestID: envelope.requestID, createdAt: now, nonce: context.sessionNonce, payload: data)

        case .appPluginActivationPrepareRequest:
            guard let payload = envelope.payload,
                  let command = Self.decodeAppPluginActivationCommand(payload),
                  command.requestID == envelope.requestID,
                  abs(command.createdAt.timeIntervalSince(envelope.createdAt)) <= 5,
                  command.validate(now: now, clockSkewLimit: clockSkewLimit) else {
                return reject(envelope, code: .malformedAppPluginActivation, operation: nil, peer: context.identity)
            }
            guard recoveryStatus() == .clean else {
                return reject(envelope, code: .pluginMutationRecoveryRequired, operation: nil, peer: context.identity)
            }
            guard let authorizer = pluginFilterMutationAuthorizer else {
                return reject(envelope, code: .dispatchNotConfigured, operation: nil, peer: context.identity)
            }
            do {
                let prepared = try authorizer.prepare(command.makeMutationRequest(), now: now)
                guard let filterBefore = prepared.response.previousPlistSHA256,
                      let filterAfter = prepared.response.proposedPlistSHA256,
                      let manifestBefore = prepared.response.previousManifestSHA256,
                      let manifestAfter = prepared.response.proposedManifestSHA256 else {
                    return reject(envelope, code: .appPluginActivationAuthorizationFailed, operation: nil, peer: context.identity)
                }
                guard let currentManifest = try? JSONDecoder().decode(FilterKitPluginManifest.self,
                    from: prepared.previousManifestData),
                    let currentAssociations = currentManifest.softAssociations else {
                    return reject(envelope, code: .appPluginActivationAuthorizationFailed, operation: nil, peer: context.identity)
                }
                let actualPreviousEnabled = currentAssociations.first(where: {
                    $0.bundleIdentifier == command.targetBundleIdentifier
                })?.isEnabled ?? false
                guard actualPreviousEnabled == command.expectedEnabled else {
                    return reject(envelope, code: .appPluginActivationAuthorizationFailed, operation: nil, peer: context.identity)
                }
                let plan = HelperAppPluginActivationPlan(requestID: command.requestID,
                    pluginID: command.pluginID, targetBundleIdentifier: command.targetBundleIdentifier,
                    previousEnabled: actualPreviousEnabled, desiredEnabled: command.desiredEnabled,
                    filterBeforeSHA256: filterBefore, filterAfterSHA256: filterAfter,
                    manifestBeforeSHA256: manifestBefore, manifestAfterSHA256: manifestAfter,
                    changed: actualPreviousEnabled != command.desiredEnabled)
                guard plan.validates(command: command) else {
                    return reject(envelope, code: .appPluginActivationAuthorizationFailed, operation: nil, peer: context.identity)
                }
                do {
                    try audit.append(HelperAuditRecord(requestID: envelope.requestID, peer: context.identity,
                        outcome: .accepted, reasonCode: plan.changed ? "app_plugin_activation_prepared_read_only" : "app_plugin_activation_already_current"))
                } catch {
                    return reject(envelope, code: .pluginMutationAuditUnavailable, operation: nil, peer: context.identity)
                }
                let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
                return HelperIPCEnvelope(messageType: .appPluginActivationPrepared,
                    requestID: envelope.requestID, createdAt: now, nonce: context.sessionNonce,
                    payload: try? encoder.encode(plan))
            } catch {
                return reject(envelope, code: .appPluginActivationAuthorizationFailed, operation: nil, peer: context.identity)
            }

        case .appPluginActivationCommitRequest:
            guard let payload = envelope.payload,
                  let commit = Self.decodeAppPluginActivationCommit(payload),
                  commit.requestID == envelope.requestID,
                  abs(commit.createdAt.timeIntervalSince(envelope.createdAt)) <= 5,
                  commit.validates(now: now, clockSkewLimit: clockSkewLimit) else {
                return reject(envelope, code: .malformedAppPluginActivation, operation: nil, peer: context.identity)
            }
            let command = commit.command
            guard recoveryStatus() == .clean else {
                return reject(envelope, code: .pluginMutationRecoveryRequired, operation: nil, peer: context.identity)
            }
            guard let authorizer = pluginFilterMutationAuthorizer,
                  let transaction = pluginAssociationTransaction else {
                return reject(envelope, code: .dispatchNotConfigured, operation: nil, peer: context.identity)
            }
            do {
                // Re-read ownership, Manifest and Filter at the commit boundary. The supplied
                // Prepare plan is accepted only if every field matches this fresh Helper result.
                let prepared = try authorizer.prepare(command.makeMutationRequest(), now: now)
                guard let currentManifest = try? JSONDecoder().decode(FilterKitPluginManifest.self,
                    from: prepared.previousManifestData),
                    let currentAssociations = currentManifest.softAssociations else {
                    return reject(envelope, code: .appPluginActivationAuthorizationFailed, operation: nil, peer: context.identity)
                }
                let actualEnabled = currentAssociations.first(where: {
                    $0.bundleIdentifier == command.targetBundleIdentifier
                })?.isEnabled ?? false
                guard actualEnabled == command.expectedEnabled,
                      let filterBefore = prepared.response.previousPlistSHA256,
                      let filterAfter = prepared.response.proposedPlistSHA256,
                      let manifestBefore = prepared.response.previousManifestSHA256,
                      let manifestAfter = prepared.response.proposedManifestSHA256 else {
                    return reject(envelope, code: .appPluginActivationAuthorizationFailed, operation: nil, peer: context.identity)
                }
                let freshPlan = HelperAppPluginActivationPlan(requestID: command.requestID,
                    pluginID: command.pluginID, targetBundleIdentifier: command.targetBundleIdentifier,
                    previousEnabled: actualEnabled, desiredEnabled: command.desiredEnabled,
                    filterBeforeSHA256: filterBefore, filterAfterSHA256: filterAfter,
                    manifestBeforeSHA256: manifestBefore, manifestAfterSHA256: manifestAfter,
                    changed: actualEnabled != command.desiredEnabled)
                guard freshPlan == commit.preparedPlan,
                      freshPlan.validates(command: command) else {
                    return reject(envelope, code: .appPluginActivationAuthorizationFailed, operation: nil, peer: context.identity)
                }
                // Production remains fail-closed. The injectable switch is only for isolated
                // transaction/dispatcher tests and is never enabled by HelperRuntime.
                guard activationCommitExecutionEnabled else {
                    return reject(envelope, code: .executionDisabled, operation: nil, peer: context.identity)
                }
                do {
                    try audit.append(HelperAuditRecord(requestID: envelope.requestID, peer: context.identity,
                        outcome: .accepted, reasonCode: "app_plugin_activation_commit_authorized"))
                } catch {
                    return reject(envelope, code: .pluginMutationAuditUnavailable, operation: nil, peer: context.identity)
                }
                let proof: HelperAppPluginActivationProof
                if prepared.disposition == .alreadyInRequestedState {
                    proof = HelperAppPluginActivationProof(requestID: command.requestID,
                        pluginID: command.pluginID, targetBundleIdentifier: command.targetBundleIdentifier,
                        enabled: command.desiredEnabled, filterSHA256: filterBefore,
                        manifestSHA256: manifestBefore, transactionID: nil, completedAt: now)
                } else {
                    let receipt = try transaction.execute(prepared)
                    proof = HelperAppPluginActivationProof(requestID: command.requestID,
                        pluginID: command.pluginID, targetBundleIdentifier: command.targetBundleIdentifier,
                        enabled: command.desiredEnabled, filterSHA256: receipt.plistSHA256,
                        manifestSHA256: receipt.manifestSHA256, transactionID: receipt.transactionID,
                        completedAt: receipt.completedAt)
                }
                guard proof.validates(command: command, now: Date(), maximumAge: 125) else {
                    // A committed transaction must never be misreported as a successful IPC proof.
                    return reject(envelope, code: .appPluginActivationAuthorizationFailed, operation: nil, peer: context.identity)
                }
                let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
                let responseData = try encoder.encode(proof)
                try? audit.append(HelperAuditRecord(requestID: envelope.requestID, peer: context.identity,
                    outcome: .accepted, reasonCode: proof.transactionID == nil
                        ? "app_plugin_activation_already_current" : "app_plugin_activation_committed"))
                return HelperIPCEnvelope(messageType: .appPluginActivationCommitted,
                    requestID: envelope.requestID, createdAt: now, nonce: context.sessionNonce,
                    payload: responseData)
            } catch {
                return reject(envelope, code: .appPluginActivationAuthorizationFailed, operation: nil, peer: context.identity)
            }

        case .pluginFilterMutationPrepareRequest:
            guard let payload = envelope.payload,
                  let request = Self.decodePluginFilterMutation(payload),
                  request.requestID == envelope.requestID,
                  abs(request.createdAt.timeIntervalSince(envelope.createdAt)) <= 5,
                  request.validateShape(now: now, clockSkewLimit: clockSkewLimit) else {
                return reject(envelope, code: .malformedPluginMutation, operation: nil, peer: context.identity)
            }
            guard recoveryStatus() == .clean else {
                return reject(envelope, code: .pluginMutationRecoveryRequired, operation: nil, peer: context.identity)
            }
            guard let authorizer = pluginFilterMutationAuthorizer else {
                return reject(envelope, code: .dispatchNotConfigured, operation: nil, peer: context.identity)
            }
            do {
                let prepared = try authorizer.prepare(request, now: now)
                let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
                let responseData = try encoder.encode(prepared.response)
                do {
                    try audit.append(HelperAuditRecord(requestID: envelope.requestID, peer: context.identity,
                        outcome: .accepted, reasonCode: prepared.disposition == .alreadyInRequestedState
                            ? "plugin_mutation_already_current" : "plugin_mutation_prepared_read_only"))
                } catch {
                    return reject(envelope, code: .pluginMutationAuditUnavailable, operation: nil, peer: context.identity)
                }
                return HelperIPCEnvelope(messageType: .pluginFilterMutationPrepared, requestID: envelope.requestID,
                    createdAt: now, nonce: context.sessionNonce, payload: responseData)
            } catch {
                return reject(envelope, code: .pluginMutationAuthorizationFailed, operation: nil, peer: context.identity)
            }

        case .pluginFilterMutationCommitRequest:
            guard let payload = envelope.payload,
                  let request = Self.decodePluginFilterMutation(payload),
                  request.requestID == envelope.requestID,
                  abs(request.createdAt.timeIntervalSince(envelope.createdAt)) <= 5,
                  request.validateShape(now: now, clockSkewLimit: clockSkewLimit) else {
                return reject(envelope, code: .malformedPluginMutation, operation: nil, peer: context.identity)
            }
            guard recoveryStatus() == .clean else {
                return reject(envelope, code: .pluginMutationRecoveryRequired, operation: nil, peer: context.identity)
            }
            guard Self.pluginAssociationCommitReleased else {
                return reject(envelope, code: .executionDisabled, operation: nil, peer: context.identity)
            }
            guard let authorizer = pluginFilterMutationAuthorizer,
                  let transaction = pluginAssociationTransaction else {
                return reject(envelope, code: .dispatchNotConfigured, operation: nil, peer: context.identity)
            }
            do {
                // Re-authorize at commit time. No prepare result or App-supplied replacement bytes
                // are trusted across the confirmation boundary.
                let prepared = try authorizer.prepare(request, now: now)
                // A durable audit acceptance is required before any write. A later completion-audit
                // failure must never turn an already-committed transaction into a rejection.
                do {
                    try audit.append(HelperAuditRecord(requestID: envelope.requestID, peer: context.identity,
                        outcome: .accepted, reasonCode: "plugin_association_commit_authorized"))
                } catch {
                    return reject(envelope, code: .pluginMutationAuditUnavailable, operation: nil, peer: context.identity)
                }
                let receipt: HelperPluginFilterMutationCommitReceipt
                if prepared.disposition == .alreadyInRequestedState {
                    receipt = HelperPluginFilterMutationCommitReceipt(requestID: request.requestID,
                        pluginID: request.pluginID, action: request.action,
                        targetBundleIdentifier: request.targetBundleIdentifier, transactionID: nil,
                        disposition: .alreadyInRequestedState,
                        plistSHA256: prepared.response.previousPlistSHA256 ?? "",
                        manifestSHA256: prepared.response.previousManifestSHA256 ?? "",
                        completedAt: now)
                } else {
                    let committed = try transaction.execute(prepared)
                    receipt = HelperPluginFilterMutationCommitReceipt(requestID: request.requestID,
                        pluginID: request.pluginID, action: request.action,
                        targetBundleIdentifier: request.targetBundleIdentifier, transactionID: committed.transactionID,
                        disposition: .committed, plistSHA256: committed.plistSHA256,
                        manifestSHA256: committed.manifestSHA256, completedAt: committed.completedAt)
                }
                let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
                let responseData = try encoder.encode(receipt)
                // Best-effort completion event only. The pre-commit authorization event is the
                // fail-closed audit barrier; do not report failure after a successful disk commit.
                try? audit.append(HelperAuditRecord(requestID: envelope.requestID, peer: context.identity,
                    outcome: .accepted, reasonCode: receipt.transactionID == nil
                        ? "plugin_association_already_current" : "plugin_association_committed"))
                return HelperIPCEnvelope(messageType: .pluginFilterMutationCommitted, requestID: envelope.requestID,
                    createdAt: now, nonce: context.sessionNonce, payload: responseData)
            } catch {
                return reject(envelope, code: .pluginMutationAuthorizationFailed, operation: nil, peer: context.identity)
            }

        case .deploymentBatchRequest:
            guard let payload = envelope.payload,
                  let batch = Self.decodeBatch(payload),
                  batch.batchID == envelope.requestID,
                  abs(batch.createdAt.timeIntervalSince(envelope.createdAt)) <= 5,
                  (try? batch.validate(now: now, clockSkewLimit: clockSkewLimit)) != nil else {
                return reject(envelope, code: .malformedBatch, operation: nil, peer: context.identity)
            }
            switch recoveryStatus() {
            case .clean: break
            case .legacyRecoveryRequired, .threeFileRecoveryRequired, .bothRecoveryRequired, .associationTransactionRecoveryRequired:
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
            // Persist the immutable batch binding only after all read-only gates pass. A process
            // restart converts an in-flight record to indeterminate and blocks automatic replay.
            let transactionID = UUID()
            switch deploymentIdempotencyLedger.begin(batchID: batch.batchID, digest: batch.batchSHA256,
                requestIDs: batch.operations.map(\.requestID), transactionID: transactionID) {
            case .accepted: break
            case .existing(.inProgress):
                return reject(envelope, code: .deploymentBatchInProgress, operation: nil, peer: context.identity)
            case .existing(.indeterminate):
                return reject(envelope, code: .deploymentBatchOutcomeUnknown, operation: nil, peer: context.identity)
            case .existing(.completed):
                return reject(envelope, code: .replayedRequest, operation: nil, peer: context.identity)
            case .existing(.rolledBack):
                return reject(envelope, code: .deploymentBatchRolledBack, operation: nil, peer: context.identity)
            case .conflict:
                return reject(envelope, code: .deploymentBatchConflict, operation: nil, peer: context.identity)
            }
            do {
                let receipt = try deploymentPipeline.execute(batch, context: context, now: now, transactionID: transactionID)
                let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
                let payload = try encoder.encode(receipt)
                guard deploymentIdempotencyLedger.finish(batchID: batch.batchID, digest: batch.batchSHA256, state: .completed) else {
                    return reject(envelope, code: .deploymentBatchOutcomeUnknown, operation: nil, peer: context.identity)
                }
                // The durable completed record is authoritative. Completion audit is best-effort
                // and must not downgrade a committed batch if the audit sink is unavailable.
                try? audit.append(HelperAuditRecord(requestID: envelope.requestID, peer: context.identity,
                    outcome: .accepted, reasonCode: "deployment_batch_committed"))
                return HelperIPCEnvelope(messageType: .deploymentBatchReceipt, requestID: envelope.requestID,
                    createdAt: now, nonce: context.sessionNonce, payload: payload)
            } catch HelperDeploymentPipeline.PipelineError.authorizationFailed {
                _ = deploymentIdempotencyLedger.finish(batchID: batch.batchID, digest: batch.batchSHA256, state: .indeterminate)
                return reject(envelope, code: .authorizationFailed, operation: nil, peer: context.identity)
            } catch HelperDeploymentPipeline.PipelineError.invalidBatch,
                    HelperDeploymentPipeline.PipelineError.proofMismatch,
                    HelperDeploymentPipeline.PipelineError.planMismatch {
                _ = deploymentIdempotencyLedger.finish(batchID: batch.batchID, digest: batch.batchSHA256, state: .indeterminate)
                return reject(envelope, code: .malformedBatch, operation: nil, peer: context.identity)
            } catch {
                _ = deploymentIdempotencyLedger.finish(batchID: batch.batchID, digest: batch.batchSHA256, state: .indeterminate)
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
            case .legacyRecoveryRequired, .threeFileRecoveryRequired, .bothRecoveryRequired, .associationTransactionRecoveryRequired:
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
        detail = HelperStartupRecoveryCheck().inspectDetailed(pluginDirectory: pluginDirectory, deploymentLedgerStore: deploymentLedgerStore)
        switch detail {
        case .clean: return .clean
        case .legacyRecoveryRequired: return .legacyRecoveryRequired
        case .threeFileRecoveryRequired: return .threeFileRecoveryRequired
        case .bothRecoveryRequired: return .bothRecoveryRequired
        case .associationTransactionRecoveryRequired: return .associationTransactionRecoveryRequired
        case .invalidJournal: return .invalidJournal
        }
    }

    private static func decodeAppPluginActivationCommand(_ data: Data) -> HelperAppPluginActivationCommand? {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(HelperAppPluginActivationCommand.self, from: data)
    }

    private static func decodeAppPluginActivationCommit(_ data: Data) -> HelperAppPluginActivationCommitRequest? {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(HelperAppPluginActivationCommitRequest.self, from: data)
    }

    private static func decodePluginIdentityAttestation(_ data: Data) -> HelperPluginIdentityAttestationRequest? {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(HelperPluginIdentityAttestationRequest.self, from: data)
    }

    private static func decodePluginFilterMutation(_ data: Data) -> HelperPluginFilterMutationRequest? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(HelperPluginFilterMutationRequest.self, from: data)
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
