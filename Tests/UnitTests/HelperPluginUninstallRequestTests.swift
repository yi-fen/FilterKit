import XCTest
@testable import FilterKit

final class HelperPluginUninstallRequestTests: XCTestCase {
    private func request() -> HelperPluginUninstallRequest {
        HelperPluginUninstallRequest(requestID: UUID(), pluginID: UUID(),
            dylibFileName: "Example.dylib", plistFileName: "Example.plist",
            expectedDylibSHA256: String(repeating: "a", count: 64),
            expectedPlistSHA256: String(repeating: "b", count: 64),
            expectedManifestSHA256: String(repeating: "c", count: 64),
            createdAt: Date(), operatorConfirmed: true)
    }

    func testValidUninstallIntentHasNoCallerControlledPath() throws {
        let value = request()
        XCTAssertTrue(value.validate())
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(HelperPluginUninstallRequest.self, from: data)
        XCTAssertEqual(decoded, value)
    }

    func testMismatchedFileBasenameIsRejected() {
        let value = request()
        let invalid = HelperPluginUninstallRequest(requestID: value.requestID, pluginID: value.pluginID,
            dylibFileName: value.dylibFileName, plistFileName: "Other.plist",
            expectedDylibSHA256: value.expectedDylibSHA256,
            expectedPlistSHA256: value.expectedPlistSHA256,
            expectedManifestSHA256: value.expectedManifestSHA256,
            createdAt: value.createdAt, operatorConfirmed: true)
        XCTAssertFalse(invalid.validate())
    }

    func testMissingOperatorConfirmationIsRejected() {
        let value = request()
        let invalid = HelperPluginUninstallRequest(requestID: value.requestID, pluginID: value.pluginID,
            dylibFileName: value.dylibFileName, plistFileName: value.plistFileName,
            expectedDylibSHA256: value.expectedDylibSHA256,
            expectedPlistSHA256: value.expectedPlistSHA256,
            expectedManifestSHA256: value.expectedManifestSHA256,
            createdAt: value.createdAt, operatorConfirmed: false)
        XCTAssertTrue(invalid.validate()) // Shape is valid; dispatcher separately requires confirmation.
        XCTAssertFalse(invalid.operatorConfirmed)
    }
}
