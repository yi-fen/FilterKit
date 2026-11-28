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
        let wrongArray = try PropertyListSerialization.data(fromPropertyList: ["Bundles": 42], format: .xml, options: 0)
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
        XCTAssertEqual(parsed.executables, ["Example"])
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

    func testAcceptsCaseInsensitiveKeysAndSingleStringTarget() throws {
        let source: [String: Any] = ["filter": [
            "bundles": "com.example.reader",
            "executables": "Reader"
        ]]
        let data = try PropertyListSerialization.data(fromPropertyList: source, format: .xml, options: 0)
        let parsed = PluginFilterConfiguration.parse(data)
        XCTAssertEqual(parsed.parseState, .valid)
        XCTAssertEqual(parsed.bundles, ["com.example.reader"])
        XCTAssertEqual(parsed.executables, ["Reader"])
    }

    func testMissingTargetFieldsAreUnknownRatherThanIndependent() throws {
        let source: [String: Any] = ["Filter": ["Classes": ["ExampleClass"], "Mode": "Any"]]
        let data = try PropertyListSerialization.data(fromPropertyList: source, format: .xml, options: 0)
        let parsed = PluginFilterConfiguration.parse(data)
        XCTAssertEqual(parsed.parseState, .partial)
        let plugin = PluginScanItem(id: "sample.dylib", baseName: "Sample", dylibFileName: "sample.dylib",
            plistFileName: "sample.plist", manifestFileName: nil, pairingState: .paired,
            binaryKind: .machO, ownership: .unknown, filterKitPluginID: nil, packageIdentifier: nil,
            dylibSHA256: nil, plistSHA256: nil, hardBoundBundleIdentifier: nil,
            softAssociatedBundleIdentifiers: [], warnings: parsed.warnings, filterConfiguration: parsed,
            managementPermission: nil)
        XCTAssertEqual(PluginAppLoadStatus.resolve(plugin: plugin, appNamesByBundleID: [:],
            appNamesByExecutable: [:]), .unknown)
    }

    func testExplicitEmptyTargetArraysCanRepresentIndependentPlugin() throws {
        let source: [String: Any] = ["Filter": ["Bundles": [String](), "Executables": [String](), "Classes": ["ExampleClass"]]]
        let data = try PropertyListSerialization.data(fromPropertyList: source, format: .xml, options: 0)
        let parsed = PluginFilterConfiguration.parse(data)
        XCTAssertEqual(parsed.parseState, .valid)
        let plugin = PluginScanItem(id: "sample.dylib", baseName: "Sample", dylibFileName: "sample.dylib",
            plistFileName: "sample.plist", manifestFileName: nil, pairingState: .paired,
            binaryKind: .machO, ownership: .unknown, filterKitPluginID: nil, packageIdentifier: nil,
            dylibSHA256: nil, plistSHA256: nil, hardBoundBundleIdentifier: nil,
            softAssociatedBundleIdentifiers: [], warnings: [], filterConfiguration: parsed,
            managementPermission: nil)
        XCTAssertEqual(PluginAppLoadStatus.resolve(plugin: plugin, appNamesByBundleID: [:],
            appNamesByExecutable: [:]), .independent)
    }

    func testCaseVariantDuplicateKeysAreMarkedPartial() throws {
        let source: [String: Any] = ["Bundles": ["com.example.one"],
                                     "bundles": ["com.example.two"],
                                     "Executables": [String]()]
        let data = try PropertyListSerialization.data(fromPropertyList: source, format: .xml, options: 0)
        let parsed = PluginFilterConfiguration.parse(data)
        XCTAssertEqual(parsed.parseState, .partial)
        XCTAssertTrue(parsed.warnings.contains("plugin_filter.duplicate_key_bundles"))
    }
}
