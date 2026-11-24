import XCTest
@testable import FilterKit

final class HelperDeploymentRouteResolverTests: XCTestCase {
    private func pair(pluginID: UUID = UUID()) -> [HelperOperationRequest] {
        let time = Date()
        return [
            HelperOperationRequest(requestID: UUID(), operation: .installDylib, pluginID: pluginID,
                stagingRelativePath: "task/Example.dylib", targetFileName: "Example.dylib",
                expectedSHA256: String(repeating: "a", count: 64), createdAt: time),
            HelperOperationRequest(requestID: UUID(), operation: .replaceFilterPlist, pluginID: pluginID,
                stagingRelativePath: "task/Example.plist", targetFileName: "Example.plist",
                expectedSHA256: String(repeating: "b", count: 64), createdAt: time)
        ]
    }

    func testFirstInstallRequiresVerifiedUnownedEvidence() throws {
        XCTAssertEqual(try HelperDeploymentRouteResolver().resolve(requests: pair(), manifestExists: false,
            ownership: .verifiedUnowned), .firstInstall)
        XCTAssertThrowsError(try HelperDeploymentRouteResolver().resolve(requests: pair(), manifestExists: false,
            ownership: .unknown))
    }

    func testUpdateRequiresFilterKitManifestOwnership() throws {
        XCTAssertEqual(try HelperDeploymentRouteResolver().resolve(requests: pair(), manifestExists: true,
            ownership: .filterKitOwned), .update)
        XCTAssertThrowsError(try HelperDeploymentRouteResolver().resolve(requests: pair(), manifestExists: true,
            ownership: .verifiedUnowned))
        XCTAssertThrowsError(try HelperDeploymentRouteResolver().resolve(requests: pair(), manifestExists: true,
            ownership: .packageManagerOwned))
    }

    func testPairMustBeAtomicAndSamePlugin() throws {
        XCTAssertNoThrow(try HelperDeploymentBatchValidator().validate(pair()))
        XCTAssertThrowsError(try HelperDeploymentBatchValidator().validate(Array(pair().prefix(1))))
        XCTAssertThrowsError(try HelperDeploymentBatchValidator().validate(pair(pluginID: UUID()).enumerated().map { index, item in
            HelperOperationRequest(requestID: item.requestID, operation: item.operation,
                pluginID: index == 0 ? UUID() : UUID(), stagingRelativePath: item.stagingRelativePath,
                targetFileName: item.targetFileName, expectedSHA256: item.expectedSHA256, createdAt: item.createdAt)
        }))
    }
}
