import XCTest
@testable import FilterKit

final class PluginAssociationCommitIntegrationTests: XCTestCase {
    func testCommitRequiresExplicitConfirmationBeforeTransport() async throws {
        let transport = CountingAssociationTransport()
        let coordinator = HelperDeploymentCoordinator(transport: transport)
        let request = HelperPluginFilterMutationRequest(requestID: UUID(), pluginID: UUID(),
            action: .enableForApp, dylibFileName: "Example.dylib", plistFileName: "Example.plist",
            targetBundleIdentifier: "com.example.target",
            expectedPlistSHA256: String(repeating: "a", count: 64),
            expectedManifestSHA256: String(repeating: "b", count: 64), createdAt: Date())
        do {
            _ = try await coordinator.commitPluginAssociation(request, userConfirmed: false)
            XCTFail("Unconfirmed commit must be rejected")
        } catch HelperDeploymentCoordinator.CoordinatorError.confirmationRequired {
            XCTAssertEqual(transport.exchangeCount, 0)
        }
    }

    func testCommitReleaseGateRemainsClosed() {
        XCTAssertFalse(HelperDeploymentCoordinator.pluginAssociationCommitReleased)
    }
}

private final class CountingAssociationTransport: HelperIPCTransport {
    private(set) var exchangeCount = 0
    func exchange(_ envelope: HelperIPCEnvelope) async throws -> HelperIPCEnvelope {
        exchangeCount += 1
        throw HelperDeploymentCoordinator.CoordinatorError.transportUnavailable
    }
}
