import XCTest
@testable import FilterKit

final class PluginAssociationModelTests: XCTestCase {
    func testHardBoundIdentityIsIndependentFromSoftAssociations() {
        let associations = PluginAssociations(
            hardBoundBundleIdentifier: "com.example.source",
            softAssociatedBundleIdentifiers: ["com.example.secondary"],
            effectiveBundleIdentifiers: ["com.example.source", "com.example.secondary"]
        )

        XCTAssertEqual(associations.hardBoundBundleIdentifier, "com.example.source")
        XCTAssertTrue(associations.softAssociatedBundleIdentifiers.contains("com.example.secondary"))
        XCTAssertTrue(associations.effectiveBundleIdentifiers.contains("com.example.source"))
    }
}
