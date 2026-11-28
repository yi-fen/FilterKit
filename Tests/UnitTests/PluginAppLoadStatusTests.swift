import XCTest
@testable import FilterKit

final class PluginAppLoadStatusTests: XCTestCase {
    private func item(bundles: [String] = [], executables: [String] = [],
                      parseState: PluginFilterParseState = .valid,
                      hardBound: String? = nil, soft: [String] = []) -> PluginScanItem {
        let filter = PluginFilterConfiguration(parseState: parseState, containerKey: "Filter",
            bundles: bundles, executables: executables, classes: [], modeDescription: nil,
            unknownKeys: [], warnings: [])
        return PluginScanItem(id: "sample.dylib", baseName: "Sample", dylibFileName: "sample.dylib",
            plistFileName: "sample.plist", manifestFileName: nil, pairingState: .paired,
            binaryKind: .machO, ownership: .unknown, filterKitPluginID: nil,
            packageIdentifier: nil, dylibSHA256: nil, plistSHA256: nil,
            hardBoundBundleIdentifier: hardBound, softAssociatedBundleIdentifiers: soft,
            warnings: [], filterConfiguration: filter, managementPermission: PluginManagementPermission(
                access: .readOnlyUnknownSource, reasonKey: "test"))
    }

    func testBundleTargetsResolveToInstalledAppDisplayNames() {
        let status = PluginAppLoadStatus.resolve(plugin: item(bundles: ["com.example.reader"]),
            appNamesByBundleID: ["com.example.reader": "Reader"], appNamesByExecutable: [:])
        XCTAssertEqual(status, .appTargets(["Reader"]))
    }

    func testOnlyObservedFilterTargetsDetermineAppLoadScope() {
        let status = PluginAppLoadStatus.resolve(plugin: item(bundles: ["com.example.owner", "com.example.extra"],
            hardBound: "com.example.owner", soft: ["com.example.extra"]),
            appNamesByBundleID: [:], appNamesByExecutable: [:])
        XCTAssertEqual(status, .appTargets(["com.example.extra", "com.example.owner"]))
    }

    func testExecutableAndGlobalTargetsAreDistinct() {
        XCTAssertEqual(PluginAppLoadStatus.resolve(plugin: item(executables: ["Reader"]),
            appNamesByBundleID: [:], appNamesByExecutable: ["reader": "Reader App"]),
            .executableTargets(["Reader App"]))
        XCTAssertEqual(PluginAppLoadStatus.resolve(plugin: item(bundles: ["*"]),
            appNamesByBundleID: [:], appNamesByExecutable: [:]), .globalTarget)
    }

    func testOnlyValidEmptyTargetConfigurationIsStandalone() {
        XCTAssertEqual(PluginAppLoadStatus.resolve(plugin: item(), appNamesByBundleID: [:],
            appNamesByExecutable: [:]), .independent)
        XCTAssertEqual(PluginAppLoadStatus.resolve(plugin: item(parseState: .partial),
            appNamesByBundleID: [:], appNamesByExecutable: [:]), .unknown)
        XCTAssertEqual(PluginAppLoadStatus.resolve(plugin: item(parseState: .invalid),
            appNamesByBundleID: [:], appNamesByExecutable: [:]), .unknown)
    }

    func testUnavailableFilterDoesNotTrustUnverifiedManifestOwnerHint() {
        let plugin = PluginScanItem(id: "sample.dylib", baseName: "Sample", dylibFileName: "sample.dylib",
            plistFileName: "sample.plist", manifestFileName: "sample.fk.json", pairingState: .paired,
            binaryKind: .machO, ownership: .unknown, filterKitPluginID: nil, packageIdentifier: nil,
            dylibSHA256: nil, plistSHA256: nil, hardBoundBundleIdentifier: "com.example.owner",
            softAssociatedBundleIdentifiers: [], warnings: [], filterConfiguration: nil,
            managementPermission: PluginManagementPermission(access: .readOnlyUnknownSource, reasonKey: "test"))
        XCTAssertEqual(PluginAppLoadStatus.resolve(plugin: plugin, appNamesByBundleID: [:],
            appNamesByExecutable: [:]), .unknown)
    }

    func testAmbiguousDuplicateTargetKeysDoNotProduceLoadTarget() {
        let filter = PluginFilterConfiguration(parseState: .partial, containerKey: "Filter",
            bundles: ["com.example.reader"], executables: ["Reader"], classes: [],
            modeDescription: nil, unknownKeys: [],
            warnings: ["plugin_filter.duplicate_key_bundles"])
        let plugin = PluginScanItem(id: "sample.dylib", baseName: "Sample", dylibFileName: "sample.dylib",
            plistFileName: "sample.plist", manifestFileName: nil, pairingState: .paired,
            binaryKind: .machO, ownership: .unknown, filterKitPluginID: nil, packageIdentifier: nil,
            dylibSHA256: nil, plistSHA256: nil, hardBoundBundleIdentifier: nil,
            softAssociatedBundleIdentifiers: [], warnings: filter.warnings, filterConfiguration: filter,
            managementPermission: nil)
        XCTAssertEqual(PluginAppLoadStatus.resolve(plugin: plugin, appNamesByBundleID: [:],
            appNamesByExecutable: [:]), .unknown)
    }
}
