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
