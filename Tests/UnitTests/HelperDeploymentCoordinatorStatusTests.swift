import XCTest
@testable import FilterKit

final class HelperDeploymentCoordinatorStatusTests: XCTestCase {
    private final class StatusTransport: HelperIPCTransport {
        var status = HelperStatusResponse(helperReachable: true, recoveryStatus: .threeFileRecoveryRequired,
                                          checkedAt: Date(), protocolVersion: HelperIPCEnvelope.currentVersion)
        var maintenanceResult: HelperMaintenanceResult = .recoveryNotReleased
        var maintenanceTransactionID: UUID?

        func exchange(_ envelope: HelperIPCEnvelope) async throws -> HelperIPCEnvelope {
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            switch envelope.messageType {
            case .healthRequest:
                return HelperIPCEnvelope(messageType: .healthResponse, requestID: envelope.requestID,
                    createdAt: Date(), nonce: envelope.nonce, payload: try encoder.encode(status))
            case .maintenanceRecoveryRequest:
                let response = HelperMaintenanceRecoveryResponse(result: maintenanceResult,
                    recoveryStatus: status.recoveryStatus, completedAt: Date(),
                    transactionID: maintenanceTransactionID)
                return HelperIPCEnvelope(messageType: .maintenanceRecoveryResponse, requestID: envelope.requestID,
                    createdAt: Date(), nonce: envelope.nonce, payload: try encoder.encode(response))
            default:
                return HelperIPCEnvelope(messageType: .rejected, requestID: envelope.requestID)
            }
        }
    }

    func testFetchStatusDecodesRecoveryState() async throws {
        let transport = StatusTransport()
        let coordinator = HelperDeploymentCoordinator(transport: transport)
        let status = try await coordinator.fetchStatus()
        XCTAssertTrue(status.helperReachable)
        XCTAssertEqual(status.recoveryStatus, .threeFileRecoveryRequired)
        let reachable = try await coordinator.healthCheck()
        XCTAssertTrue(reachable)
    }

    func testMaintenanceInspectWorksButReconcileRemainsDisabled() async throws {
        let coordinator = HelperDeploymentCoordinator(transport: StatusTransport())
        let inspection = try await coordinator.requestMaintenanceRecovery(.inspect)
        XCTAssertEqual(inspection.result, .inspected)
        do {
            _ = try await coordinator.requestMaintenanceRecovery(.reconcileThreeFileTransaction)
            XCTFail("Recovery requires explicit confirmation and a transaction ID")
        } catch let error as HelperDeploymentCoordinator.CoordinatorError {
            XCTAssertEqual(error, .confirmationRequired)
        }
        let transactionID = UUID()
        let transport = StatusTransport()
        transport.maintenanceTransactionID = transactionID
        let confirmedCoordinator = HelperDeploymentCoordinator(transport: transport)
        do {
            _ = try await confirmedCoordinator.requestMaintenanceRecovery(.reconcileThreeFileTransaction,
                transactionID: transactionID, userConfirmed: true)
            XCTFail("Recovery mutation must remain disabled")
        } catch let error as HelperDeploymentCoordinator.CoordinatorError {
            XCTAssertEqual(error, .recoveryNotReleased)
        }
    }
}
