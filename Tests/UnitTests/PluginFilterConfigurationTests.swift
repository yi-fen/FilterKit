import XCTest
@testable import FilterKit

final class PluginFilterConfigurationTests: XCTestCase {
    func testParsesNestedFilterAndPreservesUnknownFieldNames() throws {
        let source: [String: Any] = ["Filter": [
            "Bundles": ["com.example.one", "com.example.two"],
            "Executables": ["Example"],
            "Classes": ["ExampleClass"],
            "Mode": 1,
            "VendorExtension": ["keep": true]
        ]]
        let data = try PropertyListSerialization.data(fromPropertyList: source, format: .xml, options: 0)
        let parsed = PluginFilterConfiguration.parse(data)
        XCTAssertEqual(parsed.parseState, .valid)
        XCTAssertEqual(parsed.containerKey, "Filter")
        XCTAssertEqual(parsed.bundles, ["com.example.one", "com.example.two"])
        XCTAssertEqual(parsed.executables, ["Example"])
        XCTAssertEqual(parsed.classes, ["ExampleClass"])
        XCTAssertEqual(parsed.modeDescription, "1")
        XCTAssertEqual(parsed.unknownKeys, ["VendorExtension"])
    }

    func testParsesTopLevelDictionaryAndBinaryPlist() throws {
        let source: [String: Any] = ["Bundles": ["com.example.app"], "Mode": "Any"]
        let data = try PropertyListSerialization.data(fromPropertyList: source, format: .binary, options: 0)
        let parsed = PluginFilterConfiguration.parse(data)
        XCTAssertEqual(parsed.parseState, .valid)
        XCTAssertEqual(parsed.containerKey, "root")
        XCTAssertEqual(parsed.bundles, ["com.example.app"])
        XCTAssertEqual(parsed.modeDescription, "Any")
    }

    func testInvalidContainerAndWrongFieldTypesAreNotManageable() throws {
        let badContainer = try PropertyListSerialization.data(fromPropertyList: ["Filter": "bad"], format: .xml, options: 0)
        XCTAssertEqual(PluginFilterConfiguration.parse(badContainer).parseState, .invalid)
        let wrongArray = try PropertyListSerialization.data(fromPropertyList: ["Bundles": "not-array"], format: .xml, options: 0)
        XCTAssertEqual(PluginFilterConfiguration.parse(wrongArray).parseState, .partial)
    }

    func testModeBooleanAndNonStringFilterValuesRemainVisible() throws {
        let source: [String: Any] = ["Filter": [
            "Executables": ["Example", 7],
            "Classes": ["ExampleClass"],
            "Mode": true
        ]]
        let data = try PropertyListSerialization.data(fromPropertyList: source, format: .xml, options: 0)
        let parsed = PluginFilterConfiguration.parse(data)
        XCTAssertEqual(parsed.executables.count, 2)
        XCTAssertEqual(parsed.executables[0], "Example")
        XCTAssertTrue(parsed.executables[1].contains("integer"))
        XCTAssertEqual(parsed.modeDescription, "true")
        XCTAssertEqual(parsed.classes, ["ExampleClass"])
        XCTAssertEqual(parsed.parseState, .partial, "Non-string values are shown but remain a warning")
    }

    func testOnlyVerifiedFilterKitPluginGetsManagementPermission() throws {
        let data = try PropertyListSerialization.data(fromPropertyList: ["Bundles": ["com.example.app"]], format: .xml, options: 0)
        let config = PluginFilterConfiguration.parse(data)
        let verifiedID = UUID().uuidString
        let allowed = PluginManagementPermission.evaluate(ownership: .filterKit, pairing: .paired,
            binaryKind: .machO, verifiedPluginID: verifiedID, filterConfiguration: config)
        XCTAssertTrue(allowed.canModify)
        let packageOwned = PluginManagementPermission.evaluate(ownership: .packageManager, pairing: .paired,
            binaryKind: .machO, verifiedPluginID: verifiedID, filterConfiguration: config)
        XCTAssertFalse(packageOwned.canModify)
        let unknown = PluginManagementPermission.evaluate(ownership: .unknown, pairing: .paired,
            binaryKind: .machO, verifiedPluginID: verifiedID, filterConfiguration: config)
        XCTAssertFalse(unknown.canModify)
        let malformed = PluginManagementPermission.evaluate(ownership: .filterKit, pairing: .invalid,
            binaryKind: .machO, verifiedPluginID: verifiedID, filterConfiguration: config)
        XCTAssertFalse(malformed.canModify)
    }
}
