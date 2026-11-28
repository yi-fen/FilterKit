import XCTest
@testable import FilterKit

final class PluginImportInspectionTests: XCTestCase {
    func testGeneratedFilterPlistContainsOnlyTargetBundleRule() throws {
        let data = try PluginImportInspector.makeBaseFilterPlist(targetBundleIdentifier: "com.example.target")
        let parsed = PluginFilterConfiguration.parse(data)
        XCTAssertEqual(parsed.parseState, .valid)
        XCTAssertEqual(parsed.containerKey, "Filter")
        XCTAssertEqual(parsed.bundles, ["com.example.target"])
        XCTAssertTrue(parsed.executables.isEmpty)
        XCTAssertTrue(parsed.classes.isEmpty)
        XCTAssertNil(parsed.modeDescription)
        XCTAssertTrue(parsed.unknownKeys.isEmpty)
    }

    func testGeneratedFilterPlistRejectsInvalidBundleIdentifier() {
        XCTAssertThrowsError(try PluginImportInspector.makeBaseFilterPlist(targetBundleIdentifier: "../bad"))
        XCTAssertThrowsError(try PluginImportInspector.makeBaseFilterPlist(targetBundleIdentifier: "single"))
    }

    func testBundleIdentifierValidation() {
        XCTAssertTrue(PluginImportInspector.isValidBundleIdentifier("com.example.app_2"))
        XCTAssertFalse(PluginImportInspector.isValidBundleIdentifier("com..example"))
        XCTAssertFalse(PluginImportInspector.isValidBundleIdentifier("com.example/evil"))
    }
}
