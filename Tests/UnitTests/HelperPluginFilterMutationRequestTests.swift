import XCTest
@testable import FilterKit

final class HelperPluginFilterMutationRequestTests: XCTestCase {
    private func request(action: HelperPluginFilterMutationAction = .enableForApp,
                         target: String = "com.example.target") -> HelperPluginFilterMutationRequest {
        HelperPluginFilterMutationRequest(requestID: UUID(), pluginID: UUID(), action: action,
            dylibFileName: "Example.dylib", plistFileName: "Example.plist",
            targetBundleIdentifier: target, expectedPlistSHA256: String(repeating: "a", count: 64),
            expectedManifestSHA256: String(repeating: "b", count: 64), createdAt: Date())
    }

    func testValidIntentOnlyRequestPassesShapeValidation() {
        XCTAssertTrue(request().validateShape())
    }

    func testRejectsPathTraversalAndMismatchedPair() {
        let traversal = HelperPluginFilterMutationRequest(requestID: UUID(), pluginID: UUID(), action: .enableForApp,
            dylibFileName: "../Example.dylib", plistFileName: "Example.plist",
            targetBundleIdentifier: "com.example.target", expectedPlistSHA256: String(repeating: "a", count: 64),
            expectedManifestSHA256: String(repeating: "b", count: 64), createdAt: Date())
        XCTAssertFalse(traversal.validateShape())

        let mismatch = HelperPluginFilterMutationRequest(requestID: UUID(), pluginID: UUID(), action: .enableForApp,
            dylibFileName: "One.dylib", plistFileName: "Two.plist",
            targetBundleIdentifier: "com.example.target", expectedPlistSHA256: String(repeating: "a", count: 64),
            expectedManifestSHA256: String(repeating: "b", count: 64), createdAt: Date())
        XCTAssertFalse(mismatch.validateShape())
    }

    func testRejectsInvalidBundleAndStaleRequest() {
        XCTAssertFalse(request(target: "not-a-bundle-id").validateShape())
        XCTAssertFalse(request().validateShape(now: Date().addingTimeInterval(600)))
    }

    func testRequestContainsNoCallerSuppliedPathOrReplacementBytes() throws {
        let value = request()
        let data = try JSONEncoder().encode(value)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(json["path"])
        XCTAssertNil(json["replacementPlist"])
        XCTAssertNil(json["plistData"])
        XCTAssertEqual(Set(json.keys), Set(["requestID", "pluginID", "action", "dylibFileName", "plistFileName",
            "targetBundleIdentifier", "expectedPlistSHA256", "expectedManifestSHA256", "createdAt"]))
    }
}
