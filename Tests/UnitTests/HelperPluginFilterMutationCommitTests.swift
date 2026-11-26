import XCTest
@testable import FilterKit

final class HelperPluginFilterMutationCommitTests: XCTestCase {
    private final class RecordingTransport: HelperIPCTransport {
        private(set) var exchangeCount = 0
        func exchange(_ envelope: HelperIPCEnvelope) async throws -> HelperIPCEnvelope {
            exchangeCount += 1
            return envelope
        }
    }

    private func request() -> HelperPluginFilterMutationRequest {
        HelperPluginFilterMutationRequest(requestID: UUID(), pluginID: UUID(), action: .enableForApp,
            dylibFileName: "Example.dylib", plistFileName: "Example.plist",
            targetBundleIdentifier: "com.example.target", expectedPlistSHA256: String(repeating: "a", count: 64),
            expectedManifestSHA256: String(repeating: "b", count: 64), createdAt: Date())
    }

    func testCommitRequiresExplicitUserConfirmation() async {
        let transport = RecordingTransport()
        let coordinator = HelperDeploymentCoordinator(transport: transport)
        do {
            _ = try await coordinator.commitPluginAssociation(request(), userConfirmed: false)
            XCTFail("Expected confirmation requirement")
        } catch let error as HelperDeploymentCoordinator.CoordinatorError {
            XCTAssertEqual(error, .confirmationRequired)
        } catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(transport.exchangeCount, 0)
    }

    func testCommitReleaseGatePreventsIPCUntilDeviceValidation() async {
        let transport = RecordingTransport()
        let coordinator = HelperDeploymentCoordinator(transport: transport)
        do {
            _ = try await coordinator.commitPluginAssociation(request(), userConfirmed: true)
            XCTFail("Expected closed release gate")
        } catch let error as HelperDeploymentCoordinator.CoordinatorError {
            XCTAssertEqual(error, .executionNotReleased)
        } catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(transport.exchangeCount, 0)
    }
}
