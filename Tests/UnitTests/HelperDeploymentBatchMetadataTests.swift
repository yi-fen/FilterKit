import XCTest
@testable import FilterKit

final class HelperDeploymentBatchMetadataTests: XCTestCase {
    func testMetadataIsCoveredByBatchDigest() throws {
        let now = Date(), pluginID = UUID()
        let operations = [
            HelperOperationRequest(requestID: UUID(), operation: .installDylib, pluginID: pluginID,
                stagingRelativePath: "task/Demo.dylib", targetFileName: "Demo.dylib",
                expectedSHA256: String(repeating: "a", count: 64), createdAt: now),
            HelperOperationRequest(requestID: UUID(), operation: .replaceFilterPlist, pluginID: pluginID,
                stagingRelativePath: "task/Demo.plist", targetFileName: "Demo.plist",
                expectedSHA256: String(repeating: "b", count: 64), createdAt: now)
        ]
        let metadata = HelperDeploymentBatchMetadata(hardBoundBundleIdentifier: "com.example.source",
            softAssociations: [.init(bundleIdentifier: "com.example.other", isEnabled: true)])
        let batch = try HelperDeploymentBatchRequest.make(pluginID: pluginID, operations: operations,
            deploymentMetadata: metadata, createdAt: now)
        XCTAssertNoThrow(try batch.validate(now: now))
        var tampered = batch
        tampered.deploymentMetadata = .init(hardBoundBundleIdentifier: "com.example.attacker", softAssociations: [])
        XCTAssertThrowsError(try tampered.validate(now: now))
    }

    func testInvalidAssociationMetadataRejected() throws {
        let invalid = HelperDeploymentBatchMetadata(hardBoundBundleIdentifier: "not-a-bundle-id", softAssociations: [])
        XCTAssertFalse(invalid.validate())
    }
}
