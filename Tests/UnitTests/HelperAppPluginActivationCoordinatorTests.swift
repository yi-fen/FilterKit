import XCTest
@testable import FilterKit

final class HelperAppPluginActivationCoordinatorTests: XCTestCase {
    func testPrepareUsesActivationPrepareMessageAndValidatesHelperPlan() async throws {
        let command = makeCommand()
        let plan = makePlan(command: command)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let transport = ActivationMockTransport { envelope in
            XCTAssertEqual(envelope.messageType, .appPluginActivationPrepareRequest)
            XCTAssertEqual(envelope.requestID, command.requestID)
            return HelperIPCEnvelope(messageType: .appPluginActivationPrepared,
                requestID: envelope.requestID, createdAt: Date(), nonce: envelope.nonce,
                payload: try encoder.encode(plan))
        }
        let coordinator = HelperDeploymentCoordinator(transport: transport)
        let result = try await coordinator.prepareAppPluginActivation(command)
        XCTAssertEqual(result, plan)
        XCTAssertEqual(transport.exchangeCount, 1)
    }

    func testPrepareRejectsPlanBoundToDifferentTarget() async throws {
        let command = makeCommand()
        let valid = makePlan(command: command)
        let tampered = HelperAppPluginActivationPlan(requestID: valid.requestID,
            pluginID: valid.pluginID, targetBundleIdentifier: "com.other.app",
            previousEnabled: valid.previousEnabled, desiredEnabled: valid.desiredEnabled,
            filterBeforeSHA256: valid.filterBeforeSHA256, filterAfterSHA256: valid.filterAfterSHA256,
            manifestBeforeSHA256: valid.manifestBeforeSHA256, manifestAfterSHA256: valid.manifestAfterSHA256,
            changed: valid.changed)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let transport = ActivationMockTransport { envelope in
            HelperIPCEnvelope(messageType: .appPluginActivationPrepared,
                requestID: envelope.requestID, createdAt: Date(), nonce: envelope.nonce,
                payload: try encoder.encode(tampered))
        }
        let coordinator = HelperDeploymentCoordinator(transport: transport)
        do {
            _ = try await coordinator.prepareAppPluginActivation(command)
            XCTFail("A target-mismatched plan must be rejected")
        } catch let error as HelperDeploymentCoordinator.CoordinatorError {
            XCTAssertEqual(error, .invalidReceipt)
        }
    }

    func testTransactionQueryUsesFreshTransportIDAndValidatesIdentity() async throws {
        let command = makeCommand()
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let transport = ActivationMockTransport { envelope in
            XCTAssertEqual(envelope.messageType, .appPluginActivationTransactionQueryRequest)
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            let query = try decoder.decode(HelperAppPluginActivationTransactionQuery.self, from: envelope.payload!)
            XCTAssertEqual(query.requestID, envelope.requestID)
            XCTAssertEqual(query.commandRequestID, command.requestID)
            let status = HelperAppPluginActivationTransactionStatus(queryRequestID: query.requestID,
                commandRequestID: command.requestID, pluginID: command.pluginID,
                targetBundleIdentifier: command.targetBundleIdentifier, state: .outcomeUnknown,
                transactionID: UUID(), filterSHA256: nil, manifestSHA256: nil, checkedAt: Date())
            return HelperIPCEnvelope(messageType: .appPluginActivationTransactionStatusResponse,
                requestID: envelope.requestID, createdAt: Date(), nonce: envelope.nonce,
                payload: try encoder.encode(status))
        }
        let coordinator = HelperDeploymentCoordinator(transport: transport)
        let status = try await coordinator.queryAppPluginActivationTransaction(
            commandRequestID: command.requestID, pluginID: command.pluginID,
            targetBundleIdentifier: command.targetBundleIdentifier)
        XCTAssertEqual(status.state, .outcomeUnknown)
        XCTAssertEqual(transport.exchangeCount, 1)
    }

    func testExplicitReconciliationUsesSeparateConfirmedRequestAndValidatesStatus() async throws {
        let command = makeCommand()
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let transport = ActivationMockTransport { envelope in
            XCTAssertEqual(envelope.messageType, .appPluginActivationTransactionReconcileRequest)
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            let request = try decoder.decode(HelperAppPluginActivationTransactionReconciliationRequest.self,
                from: envelope.payload!)
            XCTAssertEqual(request.requestID, envelope.requestID)
            XCTAssertEqual(request.commandRequestID, command.requestID)
            XCTAssertTrue(request.operatorConfirmed)
            let status = HelperAppPluginActivationTransactionStatus(queryRequestID: request.requestID,
                commandRequestID: command.requestID, pluginID: command.pluginID,
                targetBundleIdentifier: command.targetBundleIdentifier, state: .committed,
                transactionID: UUID(), filterSHA256: String(repeating: "c", count: 64),
                manifestSHA256: String(repeating: "d", count: 64), checkedAt: Date())
            return HelperIPCEnvelope(messageType: .appPluginActivationTransactionStatusResponse,
                requestID: envelope.requestID, createdAt: Date(), nonce: envelope.nonce,
                payload: try encoder.encode(status))
        }
        let coordinator = HelperDeploymentCoordinator(transport: transport)
        let status = try await coordinator.reconcileAppPluginActivationTransaction(
            commandRequestID: command.requestID, pluginID: command.pluginID,
            targetBundleIdentifier: command.targetBundleIdentifier, userConfirmed: true)
        XCTAssertEqual(status.state, .committed)
        XCTAssertEqual(transport.exchangeCount, 1)
    }

    func testExplicitReconciliationRequiresUserConfirmation() async throws {
        let command = makeCommand()
        let transport = ActivationMockTransport { _ in
            XCTFail("Reconciliation must not reach Helper without confirmation")
            return HelperIPCEnvelope(messageType: .rejected)
        }
        let coordinator = HelperDeploymentCoordinator(transport: transport)
        do {
            _ = try await coordinator.reconcileAppPluginActivationTransaction(
                commandRequestID: command.requestID, pluginID: command.pluginID,
                targetBundleIdentifier: command.targetBundleIdentifier, userConfirmed: false)
            XCTFail("Explicit reconciliation requires confirmation")
        } catch let error as HelperDeploymentCoordinator.CoordinatorError {
            XCTAssertEqual(error, .confirmationRequired)
        }
        XCTAssertEqual(transport.exchangeCount, 0)
    }

    func testCommitRemainsClosedBeforeTransportSubmission() async throws {
        let command = makeCommand()
        let plan = makePlan(command: command)
        let transport = ActivationMockTransport { _ in XCTFail("Commit must not reach transport while gate is closed");
            return HelperIPCEnvelope(messageType: .rejected) }
        let coordinator = HelperDeploymentCoordinator(transport: transport)
        do {
            _ = try await coordinator.commitAppPluginActivation(command,
                preparedPlan: plan, userConfirmed: true)
            XCTFail("Commit release gate must remain closed")
        } catch let error as HelperDeploymentCoordinator.CoordinatorError {
            XCTAssertEqual(error, .executionNotReleased)
        }
        XCTAssertEqual(transport.exchangeCount, 0)
    }

    func testCommitRequiresExplicitConfirmation() async throws {
        let command = makeCommand()
        let plan = makePlan(command: command)
        let transport = ActivationMockTransport { _ in XCTFail("No transport expected without confirmation");
            return HelperIPCEnvelope(messageType: .rejected) }
        let coordinator = HelperDeploymentCoordinator(transport: transport)
        do {
            _ = try await coordinator.commitAppPluginActivation(command,
                preparedPlan: plan, userConfirmed: false)
            XCTFail("Missing confirmation must be rejected")
        } catch let error as HelperDeploymentCoordinator.CoordinatorError {
            XCTAssertEqual(error, .confirmationRequired)
        }
        XCTAssertEqual(transport.exchangeCount, 0)
    }

    private func makeCommand() -> HelperAppPluginActivationCommand {
        HelperAppPluginActivationCommand(requestID: UUID(), pluginID: UUID(),
            targetBundleIdentifier: "com.example.target", desiredEnabled: true, expectedEnabled: false,
            dylibFileName: "Sample.dylib", plistFileName: "Sample.plist",
            expectedFilterSHA256: String(repeating: "a", count: 64),
            expectedManifestSHA256: String(repeating: "b", count: 64),
            snapshotRevision: 4, createdAt: Date())
    }

    private func makePlan(command: HelperAppPluginActivationCommand) -> HelperAppPluginActivationPlan {
        HelperAppPluginActivationPlan(requestID: command.requestID, pluginID: command.pluginID,
            targetBundleIdentifier: command.targetBundleIdentifier, previousEnabled: false,
            desiredEnabled: true, filterBeforeSHA256: command.expectedFilterSHA256,
            filterAfterSHA256: String(repeating: "c", count: 64),
            manifestBeforeSHA256: command.expectedManifestSHA256,
            manifestAfterSHA256: String(repeating: "d", count: 64), changed: true)
    }
}

private final class ActivationMockTransport: HelperIPCTransport {
    private let handler: (HelperIPCEnvelope) throws -> HelperIPCEnvelope
    private(set) var exchangeCount = 0

    init(handler: @escaping (HelperIPCEnvelope) throws -> HelperIPCEnvelope) {
        self.handler = handler
    }

    func exchange(_ envelope: HelperIPCEnvelope) async throws -> HelperIPCEnvelope {
        exchangeCount += 1
        return try handler(envelope)
    }
}
