import XCTest
@testable import FilterKit

final class RootHideElleKitFilterStrategyTests: XCTestCase {
    private let strategy = RootHideElleKitFilterStrategy()
    private let target = "com.example.target"

    private func plist(_ filter: [String: Any], extra: [String: Any] = [:]) throws -> Data {
        var root: [String: Any] = ["Filter": filter, "IsTweakManager": false, "VendorKey": "preserve-me"]
        for (key, value) in extra { root[key] = value }
        return try PropertyListSerialization.data(fromPropertyList: root, format: .xml, options: 0)
    }

    func testEnableAddsBundleAndPreservesUnknownKeysAndVersionGate() throws {
        let input = try plist(["Bundles": ["com.example.other"], "CoreFoundationVersion": [1900], "VendorFilterKey": ["x"]])
        let result = strategy.makePlan(originalData: input, targetBundleIdentifier: target, action: .enableForApp)
        XCTAssertEqual(result.disposition, .previewReady)
        XCTAssertEqual(result.afterBundles, ["com.example.other", target])
        XCTAssertEqual(result.preservedRootKeys, ["VendorKey"])
        XCTAssertEqual(result.preservedFilterKeys, ["VendorFilterKey"])
        let output = try XCTUnwrap(result.previewPropertyList)
        let root = try XCTUnwrap(PropertyListSerialization.propertyList(from: output, options: [], format: nil) as? [String: Any])
        let filter = try XCTUnwrap(root["Filter"] as? [String: Any])
        XCTAssertEqual(filter["CoreFoundationVersion"] as? [Int], [1900])
        XCTAssertEqual(filter["VendorFilterKey"] as? [String], ["x"])
        XCTAssertEqual(root["VendorKey"] as? String, "preserve-me")
    }

    func testDisableBundleOnlyFilterCreatesPreview() throws {
        let input = try plist(["Bundles": [target, "com.example.other"]])
        let result = strategy.makePlan(originalData: input, targetBundleIdentifier: target, action: .disableForApp)
        XCTAssertEqual(result.disposition, .previewReady)
        XCTAssertEqual(result.afterBundles, ["com.example.other"])
    }

    func testDisableBlockedWhenClassesCanStillMatch() throws {
        let input = try plist(["Bundles": [target], "Classes": ["SomeRuntimeClass"]])
        let result = strategy.makePlan(originalData: input, targetBundleIdentifier: target, action: .disableForApp)
        XCTAssertEqual(result.disposition, .blocked)
        XCTAssertTrue(result.blockers.contains(.alternateMatchDimensionsPreventSafeDisable))
        XCTAssertNil(result.previewPropertyList)
    }

    func testDisableBlockedWhenExecutablesCanStillMatch() throws {
        let input = try plist(["Bundles": [target], "Executables": ["TargetExecutable"]])
        let result = strategy.makePlan(originalData: input, targetBundleIdentifier: target, action: .disableForApp)
        XCTAssertEqual(result.disposition, .blocked)
    }

    func testAlreadyAssociatedDoesNotRewrite() throws {
        let input = try plist(["Bundles": [target]])
        let result = strategy.makePlan(originalData: input, targetBundleIdentifier: target, action: .enableForApp)
        XCTAssertEqual(result.disposition, .alreadyAssociated)
        XCTAssertNil(result.previewPropertyList)
    }

    func testMalformedRecognizedFieldFailsClosed() throws {
        let input = try plist(["Bundles": target])
        let result = strategy.makePlan(originalData: input, targetBundleIdentifier: target, action: .enableForApp)
        XCTAssertEqual(result.disposition, .blocked)
        XCTAssertTrue(result.blockers.contains(.invalidBundlesType))
    }

    func testMissingFilterDictionaryFailsClosed() throws {
        let input = try PropertyListSerialization.data(fromPropertyList: ["NotFilter": [:]], format: .xml, options: 0)
        let result = strategy.makePlan(originalData: input, targetBundleIdentifier: target, action: .enableForApp)
        XCTAssertEqual(result.disposition, .blocked)
        XCTAssertTrue(result.blockers.contains(.filterDictionaryMissing))
    }

    func testEmptyBundlesButAlternateDimensionsCannotClaimDisabled() throws {
        let input = try plist(["Classes": ["SomeRuntimeClass"]])
        let result = strategy.makePlan(originalData: input, targetBundleIdentifier: target, action: .disableForApp)
        XCTAssertEqual(result.disposition, .blocked)
    }
    func testBundleIdentifiersAreMatchedWithoutCaseSensitivityAndDuplicatesFailClosed() throws {
        let singleVariant = try plist(["Bundles": ["COM.EXAMPLE.APP"]])
        let existing = strategy.makePlan(originalData: singleVariant,
            targetBundleIdentifier: "com.example.app", action: .enableForApp)
        XCTAssertEqual(existing.disposition, .alreadyAssociated)

        let duplicates = try plist(["Bundles": ["COM.EXAMPLE.APP", "com.example.app"]])
        let blocked = strategy.makePlan(originalData: duplicates,
            targetBundleIdentifier: "com.example.app", action: .disableForApp)
        XCTAssertEqual(blocked.disposition, .blocked)
        XCTAssertTrue(blocked.blockers.contains(.duplicateBundleIdentifiers))
    }

}
