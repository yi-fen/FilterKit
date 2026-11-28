import Foundation

protocol HelperIPCTransport {
    func exchange(_ envelope: HelperIPCEnvelope) async throws -> HelperIPCEnvelope
}

/// App-side coordinator. The production transport and deployment execution remain unavailable
/// until the jailbreak-specific socket implementation and on-device identity checks are proven.
final class HelperDeploymentCoordinator {
    enum CoordinatorError: Error, Equatable { case transportUnavailable, invalidHandshake, invalidReceipt, invalidBatch, invalidStatus, recoveryNotReleased, executionNotReleased, confirmationRequired, mutationRejected }
    static let executionReleased = false
    static let pluginAssociationCommitReleased = false

    private let transport: HelperIPCTransport
    private let clockSkewLimit: TimeInterval

    init(transport: HelperIPCTransport, clockSkewLimit: TimeInterval = 120) {
        self.transport = transport
        self.clockSkewLimit = clockSkewLimit
    }

    func fetchStatus() async throws -> HelperStatusResponse {
        let request = HelperIPCEnvelope(messageType: .healthRequest)
        let response = try await transport.exchange(request)
        guard response.protocolVersion == HelperIPCEnvelope.currentVersion,
              response.messageType == .healthResponse,
              response.requestID == request.requestID,
              let payload = response.payload else { throw CoordinatorError.invalidStatus }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let status = try decoder.decode(HelperStatusResponse.self, from: payload)
        guard status.helperReachable,
              status.protocolVersion == HelperIPCEnvelope.currentVersion,
              abs(Date().timeIntervalSince(status.checkedAt)) <= clockSkewLimit else {
            throw CoordinatorError.invalidStatus
        }
        return status
    }

    /// Compatibility convenience for older callers. A valid status payload is required.
    func healthCheck() async throws -> Bool {
        try await fetchStatus().helperReachable
    }

    func requestMaintenanceRecovery(_ action: HelperMaintenanceAction,
                                    transactionID: UUID? = nil,
                                    userConfirmed: Bool = false) async throws -> HelperMaintenanceRecoveryResponse {
        if action == .reconcileThreeFileTransaction && (!userConfirmed || transactionID == nil) {
            throw CoordinatorError.confirmationRequired
        }
        let now = Date()
        let requestID = UUID()
        let requestBody = HelperMaintenanceRecoveryRequest(action: action, requestNonce: requestID,
            requestedAt: now, transactionID: transactionID, operatorConfirmed: userConfirmed)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let envelope = HelperIPCEnvelope(messageType: .maintenanceRecoveryRequest, requestID: requestID,
                                         createdAt: now, payload: try encoder.encode(requestBody))
        let response = try await transport.exchange(envelope)
        guard response.protocolVersion == HelperIPCEnvelope.currentVersion,
              response.messageType == .maintenanceRecoveryResponse,
              response.requestID == envelope.requestID,
              let payload = response.payload else { throw CoordinatorError.invalidStatus }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let result = try decoder.decode(HelperMaintenanceRecoveryResponse.self, from: payload)
        guard abs(Date().timeIntervalSince(result.completedAt)) <= clockSkewLimit else {
            throw CoordinatorError.invalidStatus
        }
        if action == .reconcileThreeFileTransaction {
            guard result.transactionID == transactionID else { throw CoordinatorError.invalidStatus }
            if result.result == .recoveryNotReleased { throw CoordinatorError.recoveryNotReleased }
        }
        return result
    }


    /// Requests a read-only Helper-authored identity attestation. No mutation API is called.
    func attestPluginIdentity(pluginID: UUID, dylibFileName: String, plistFileName: String) async throws -> HelperPluginIdentityAttestation {
        let now = Date()
        let request = HelperPluginIdentityAttestationRequest(requestID: UUID(), pluginID: pluginID,
            dylibFileName: dylibFileName, plistFileName: plistFileName, createdAt: now)
        guard request.validate(now: now, clockSkewLimit: clockSkewLimit) else { throw CoordinatorError.mutationRejected }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let envelope = HelperIPCEnvelope(messageType: .pluginIdentityAttestationRequest,
            requestID: request.requestID, createdAt: now, payload: try encoder.encode(request))
        let response = try await transport.exchange(envelope)
        guard response.protocolVersion == HelperIPCEnvelope.currentVersion,
              response.messageType == .pluginIdentityAttestationResponse,
              response.requestID == request.requestID, let payload = response.payload else {
            throw CoordinatorError.invalidStatus
        }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let result = try decoder.decode(HelperPluginIdentityAttestation.self, from: payload)
        guard result.requestID == request.requestID,
              abs(Date().timeIntervalSince(result.completedAt)) <= clockSkewLimit else {
            throw CoordinatorError.invalidStatus
        }
        return result
    }

    /// Sends a user-confirmed association intent. Helper re-reads ownership and both source files
    /// immediately before the two-file transaction; no replacement bytes cross IPC.
    /// This client-side release gate intentionally remains closed until device validation.
    func commitPluginAssociation(_ request: HelperPluginFilterMutationRequest,
                                 userConfirmed: Bool) async throws -> HelperPluginFilterMutationCommitReceipt {
        guard userConfirmed else { throw CoordinatorError.confirmationRequired }
        guard Self.pluginAssociationCommitReleased else { throw CoordinatorError.executionNotReleased }
        guard request.validateShape(), request.requestID != UUID(uuidString: "00000000-0000-0000-0000-000000000000") else {
            throw CoordinatorError.mutationRejected
        }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let envelope = HelperIPCEnvelope(messageType: .pluginFilterMutationCommitRequest,
            requestID: request.requestID, createdAt: request.createdAt, payload: try encoder.encode(request))
        let response = try await transport.exchange(envelope)
        guard response.protocolVersion == HelperIPCEnvelope.currentVersion,
              response.messageType == .pluginFilterMutationCommitted,
              response.requestID == request.requestID, let payload = response.payload else {
            throw CoordinatorError.invalidReceipt
        }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let receipt = try decoder.decode(HelperPluginFilterMutationCommitReceipt.self, from: payload)
        guard receipt.requestID == request.requestID, receipt.pluginID == request.pluginID,
              receipt.action == request.action, receipt.targetBundleIdentifier == request.targetBundleIdentifier,
              ((receipt.disposition == .committed && receipt.transactionID != nil) ||
               (receipt.disposition == .alreadyInRequestedState && receipt.transactionID == nil)),
              HelperPolicy.isValidHash(receipt.plistSHA256), HelperPolicy.isValidHash(receipt.manifestSHA256),
              abs(Date().timeIntervalSince(receipt.completedAt)) <= clockSkewLimit else {
            throw CoordinatorError.invalidReceipt
        }
        return receipt
    }

    /// Read-only activation Prepare. Helper independently re-reads ownership and both files.
    func prepareAppPluginActivation(_ command: HelperAppPluginActivationCommand) async throws -> HelperAppPluginActivationPlan {
        guard command.validate(clockSkewLimit: clockSkewLimit) else { throw CoordinatorError.mutationRejected }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let envelope = HelperIPCEnvelope(messageType: .appPluginActivationPrepareRequest,
            requestID: command.requestID, createdAt: command.createdAt, payload: try encoder.encode(command))
        let response = try await transport.exchange(envelope)
        guard response.protocolVersion == HelperIPCEnvelope.currentVersion,
              response.messageType == .appPluginActivationPrepared,
              response.requestID == command.requestID, let payload = response.payload else {
            throw CoordinatorError.invalidReceipt
        }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let plan = try decoder.decode(HelperAppPluginActivationPlan.self, from: payload)
        guard plan.validates(command: command) else { throw CoordinatorError.invalidReceipt }
        return plan
    }

    /// Sends the exact Prepare plan using a fresh transport request ID. Commit remains
    /// fail-closed in the App until the separately reviewed device release gate is opened.
    func commitAppPluginActivation(_ command: HelperAppPluginActivationCommand,
                                   preparedPlan: HelperAppPluginActivationPlan,
                                   userConfirmed: Bool) async throws -> HelperAppPluginActivationProof {
        guard userConfirmed else { throw CoordinatorError.confirmationRequired }
        guard preparedPlan.validates(command: command) else { throw CoordinatorError.mutationRejected }
        guard Self.appPluginActivationCommitReleased else { throw CoordinatorError.executionNotReleased }
        let now = Date()
        let commit = HelperAppPluginActivationCommitRequest(requestID: UUID(), createdAt: now,
            command: command, preparedPlan: preparedPlan)
        guard commit.validates(now: now, clockSkewLimit: clockSkewLimit) else {
            throw CoordinatorError.mutationRejected
        }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let envelope = HelperIPCEnvelope(messageType: .appPluginActivationCommitRequest,
            requestID: commit.requestID, createdAt: now, payload: try encoder.encode(commit))
        let response: HelperIPCEnvelope
        do { response = try await transport.exchange(envelope) }
        catch { throw CoordinatorError.invalidReceipt } // Caller must rescan; commit outcome is not assumed.
        guard response.protocolVersion == HelperIPCEnvelope.currentVersion,
              response.messageType == .appPluginActivationCommitted,
              response.requestID == commit.requestID, let payload = response.payload else {
            throw CoordinatorError.invalidReceipt
        }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let proof = try decoder.decode(HelperAppPluginActivationProof.self, from: payload)
        guard proof.validates(command: command, now: Date(), maximumAge: clockSkewLimit + 5) else {
            throw CoordinatorError.invalidReceipt
        }
        return proof
    }

    /// Read-only lookup by the original APP command ID. A fresh transport request ID is used
    /// for every query so replay protection does not prevent reconnect/status recovery.
    func queryAppPluginActivationTransaction(commandRequestID: UUID, pluginID: UUID,
                                             targetBundleIdentifier: String) async throws -> HelperAppPluginActivationTransactionStatus {
        let now = Date()
        let query = HelperAppPluginActivationTransactionQuery(requestID: UUID(),
            commandRequestID: commandRequestID, pluginID: pluginID,
            targetBundleIdentifier: targetBundleIdentifier, createdAt: now)
        guard query.validate(now: now, clockSkewLimit: clockSkewLimit) else {
            throw CoordinatorError.mutationRejected
        }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let envelope = HelperIPCEnvelope(messageType: .appPluginActivationTransactionQueryRequest,
            requestID: query.requestID, createdAt: now, payload: try encoder.encode(query))
        let response = try await transport.exchange(envelope)
        guard response.protocolVersion == HelperIPCEnvelope.currentVersion,
              response.messageType == .appPluginActivationTransactionStatusResponse,
              response.requestID == query.requestID, let payload = response.payload else {
            throw CoordinatorError.invalidStatus
        }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let status = try decoder.decode(HelperAppPluginActivationTransactionStatus.self, from: payload)
        guard status.matches(query),
              abs(Date().timeIntervalSince(status.checkedAt)) <= clockSkewLimit else {
            throw CoordinatorError.invalidStatus
        }
        return status
    }

    /// Explicitly asks Helper to reconcile a pending Outcome Unknown activation. The request
    /// cannot replay Commit; Helper may only resolve the Ledger from its matching journal and
    /// observed file hashes, then clean that journal after the terminal Ledger write.
    func reconcileAppPluginActivationTransaction(commandRequestID: UUID, pluginID: UUID,
                                                  targetBundleIdentifier: String,
                                                  userConfirmed: Bool) async throws -> HelperAppPluginActivationTransactionStatus {
        guard userConfirmed else { throw CoordinatorError.confirmationRequired }
        let now = Date()
        let request = HelperAppPluginActivationTransactionReconciliationRequest(
            requestID: UUID(), commandRequestID: commandRequestID, pluginID: pluginID,
            targetBundleIdentifier: targetBundleIdentifier, createdAt: now, operatorConfirmed: true)
        guard request.validate(now: now, clockSkewLimit: clockSkewLimit) else {
            throw CoordinatorError.mutationRejected
        }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let envelope = HelperIPCEnvelope(messageType: .appPluginActivationTransactionReconcileRequest,
            requestID: request.requestID, createdAt: now, payload: try encoder.encode(request))
        let response = try await transport.exchange(envelope)
        guard response.protocolVersion == HelperIPCEnvelope.currentVersion,
              response.messageType == .appPluginActivationTransactionStatusResponse,
              response.requestID == request.requestID, let payload = response.payload else {
            throw CoordinatorError.invalidStatus
        }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let status = try decoder.decode(HelperAppPluginActivationTransactionStatus.self, from: payload)
        guard status.matches(request.statusQuery),
              abs(Date().timeIntervalSince(status.checkedAt)) <= clockSkewLimit else {
            throw CoordinatorError.invalidStatus
        }
        return status
    }

    static let appPluginActivationCommitReleased = false

    /// Constructs the single-envelope batch protocol. This is also used by offline protocol tests;
    /// transport submission remains blocked by the independent release gate.
    func makeBatchEnvelope(_ operations: [HelperOperationRequest],
                           deploymentMetadata: HelperDeploymentBatchMetadata? = nil,
                           createdAt: Date = Date()) throws -> HelperIPCEnvelope {
        guard let pluginID = operations.first?.pluginID,
              operations.allSatisfy({ $0.pluginID == pluginID }) else { throw CoordinatorError.invalidBatch }
        let batch = try HelperDeploymentBatchRequest.make(pluginID: pluginID, operations: operations,
            deploymentMetadata: deploymentMetadata, createdAt: createdAt)
        try batch.validate(now: createdAt)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        return HelperIPCEnvelope(messageType: .deploymentBatchRequest, requestID: batch.batchID,
                                 createdAt: createdAt, payload: try encoder.encode(batch))
    }

    func submitBatch(_ operations: [HelperOperationRequest],
                     deploymentMetadata: HelperDeploymentBatchMetadata? = nil) async throws -> HelperIPCEnvelope {
        guard Self.executionReleased else { throw CoordinatorError.executionNotReleased }
        let envelope = try makeBatchEnvelope(operations, deploymentMetadata: deploymentMetadata)
        return try await transport.exchange(envelope)
    }

    func submit(_ request: HelperOperationRequest, expectedChangedPaths: Set<String>) async throws -> HelperOperationReceipt {
        guard Self.executionReleased else { throw CoordinatorError.executionNotReleased }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let envelope = HelperIPCEnvelope(messageType: .operationRequest, requestID: request.requestID,
                                         payload: try encoder.encode(request))
        let response = try await transport.exchange(envelope)
        guard response.protocolVersion == HelperIPCEnvelope.currentVersion,
              response.messageType == .operationReceipt,
              response.requestID == request.requestID,
              let payload = response.payload else { throw CoordinatorError.invalidReceipt }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let receipt = try decoder.decode(HelperOperationReceipt.self, from: payload)
        guard receipt.validates(against: request, expectedPaths: expectedChangedPaths,
                                now: Date(), clockSkewLimit: clockSkewLimit) else {
            throw CoordinatorError.invalidReceipt
        }
        return receipt
    }
}
