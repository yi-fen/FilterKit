import XCTest
@testable import FilterKit

final class PluginListScopeTests: XCTestCase {
    private func item(ownership: PluginOwnership, hardBound: String? = nil,
                      soft: [String] = [], enabledBundles: [String] = [],
                      softStates: [FilterKitManifestSoftAssociation] = []) -> PluginScanItem {
        PluginScanItem(id: "sample.dylib", baseName: "sample", dylibFileName: "sample.dylib",
            plistFileName: "sample.plist", manifestFileName: nil, pairingState: .paired,
            binaryKind: .machO, ownership: ownership, filterKitPluginID: nil,
            packageIdentifier: nil, dylibSHA256: nil, plistSHA256: nil,
            hardBoundBundleIdentifier: hardBound, softAssociatedBundleIdentifiers: soft, warnings: [],
            filterConfiguration: PluginFilterConfiguration(parseState: .valid, containerKey: "Filter",
                bundles: enabledBundles, executables: [], classes: [], modeDescription: nil,
                unknownKeys: [], warnings: []), managementPermission: nil,
            softAssociationStates: softStates)
    }

    func testAllScopeIncludesEveryPairedPluginRegardlessOfOwnership() {
        XCTAssertTrue(PluginListScope.includes(item(ownership: .unknown), filterKitAssociatedOnly: false))
        XCTAssertTrue(PluginListScope.includes(item(ownership: .packageManager), filterKitAssociatedOnly: false))
    }

    func testNarrowScopeRequiresFilterKitOwnershipAndAnyAppAssociation() {
        let fixedOwnerEnabled = item(ownership: .filterKit, hardBound: "com.example.app", enabledBundles: ["com.example.app"])
        let fixedOwnerDisabled = item(ownership: .filterKit, hardBound: "com.example.app", enabledBundles: [])
        let additionalOnly = item(ownership: .filterKit, soft: ["com.example.app"])
        XCTAssertTrue(PluginListScope.includes(fixedOwnerEnabled, filterKitAssociatedOnly: true))
        XCTAssertTrue(PluginListScope.includes(fixedOwnerDisabled, filterKitAssociatedOnly: true), "Disabled associations remain in the associated scope")
        XCTAssertTrue(PluginListScope.includes(additionalOnly, filterKitAssociatedOnly: true))
        XCTAssertFalse(PluginListScope.includes(item(ownership: .filterKit), filterKitAssociatedOnly: true))
        XCTAssertFalse(PluginListScope.includes(item(ownership: .packageManager, hardBound: "com.example.app"), filterKitAssociatedOnly: true))
        XCTAssertFalse(PluginListScope.includes(item(ownership: .unknown, soft: ["com.example.app"]), filterKitAssociatedOnly: true))
    }

    func testFixedOwnerIsFirstAndInjectionSummaryCountsPerApp() {
        let plugin = item(ownership: .filterKit, hardBound: "com.owner.app",
            soft: ["com.second.app", "com.third.app"], enabledBundles: ["com.owner.app", "com.second.app"],
            softStates: [
                FilterKitManifestSoftAssociation(bundleIdentifier: "com.second.app", isEnabled: true),
                FilterKitManifestSoftAssociation(bundleIdentifier: "com.third.app", isEnabled: false)
            ])
        let status = PluginListStatus(item: plugin)
        XCTAssertEqual(status.apps.first?.bundleIdentifier, "com.owner.app")
        XCTAssertEqual(status.apps.first?.isFixedOwner, true)
        XCTAssertEqual(status.apps.count, 3)
        XCTAssertEqual(status.enabledCount, 2)
        XCTAssertEqual(status.disabledCount, 1)
        XCTAssertEqual(status.unknownCount, 0)
        XCTAssertEqual(status.managementType, .appAssociated)
    }

    func testPluginWithoutAppAssociationIsStandalone() {
        let status = PluginListStatus(item: item(ownership: .filterKit))
        XCTAssertEqual(status.managementType, .standalone)
        XCTAssertFalse(status.hasAppAssociation)
    }
    func testAdditionalAssociationsAreTrimmedAndDeduplicatedCaseInsensitively() {
        let plugin = item(ownership: .filterKit, hardBound: "com.Owner.App",
            soft: [" com.owner.app ", "COM.SECOND.APP", "com.second.app", "com.third.app"],
            enabledBundles: ["com.Owner.App", "com.second.app"],
            softStates: [
                FilterKitManifestSoftAssociation(bundleIdentifier: "COM.SECOND.APP", isEnabled: true),
                FilterKitManifestSoftAssociation(bundleIdentifier: "com.third.app", isEnabled: false)
            ])
        let status = PluginListStatus(item: plugin)
        XCTAssertEqual(status.apps.map(\.bundleIdentifier), ["com.Owner.App", "COM.SECOND.APP", "com.third.app"])
        XCTAssertEqual(status.apps.first?.isFixedOwner, true)
        XCTAssertEqual(status.enabledCount, 2)
        XCTAssertEqual(status.disabledCount, 1)
        XCTAssertEqual(status.unknownCount, 0)
    }

    func testDuplicateAssociationStateIsUnknownRatherThanChoosingOne() {
        let plugin = item(ownership: .filterKit, hardBound: "com.owner.app",
            soft: ["com.second.app"], enabledBundles: ["com.owner.app", "com.second.app"],
            softStates: [
                FilterKitManifestSoftAssociation(bundleIdentifier: "com.second.app", isEnabled: true),
                FilterKitManifestSoftAssociation(bundleIdentifier: "COM.SECOND.APP", isEnabled: false)
            ])
        let status = PluginListStatus(item: plugin)
        XCTAssertEqual(status.apps.count, 2)
        XCTAssertEqual(status.apps[1].injection, .unknown)
        XCTAssertEqual(status.unknownCount, 1)
    }

    func testThirdPartyFilterBundlesAreDisplayedAsTargetsNotStandaloneOwnership() {
        let plugin = item(ownership: .packageManager, enabledBundles: ["com.example.mail", "com.example.browser"])
        let target = PluginTargetDisplay.resolve(plugin)
        XCTAssertEqual(target.kind, .bundles)
        XCTAssertEqual(target.bundleIdentifiers, ["com.example.browser", "com.example.mail"])
    }

    func testWildcardFilterIsDisplayedAsAllApps() {
        let plugin = item(ownership: .unknown, enabledBundles: ["*"])
        XCTAssertEqual(PluginTargetDisplay.resolve(plugin).kind, .allApps)
    }

    func testExecutableOrClassFilterIsNotMisreportedAsStandalone() {
        let base = item(ownership: .packageManager)
        let plugin = PluginScanItem(id: base.id, baseName: base.baseName,
            dylibFileName: base.dylibFileName, plistFileName: base.plistFileName,
            manifestFileName: nil, pairingState: .paired, binaryKind: .machO,
            ownership: .packageManager, filterKitPluginID: nil, packageIdentifier: nil,
            dylibSHA256: nil, plistSHA256: nil, hardBoundBundleIdentifier: nil,
            softAssociatedBundleIdentifiers: [], warnings: [],
            filterConfiguration: PluginFilterConfiguration(parseState: .valid, containerKey: "Filter",
                bundles: [], executables: ["SpringBoard"], classes: [], modeDescription: nil,
                unknownKeys: [], warnings: []), managementPermission: nil)
        XCTAssertEqual(PluginTargetDisplay.resolve(plugin).kind, .executableRules)
    }

    func testMissingFilterTargetMetadataIsUnrecognizedRatherThanStandalone() {
        let plugin = item(ownership: .unknown)
        XCTAssertEqual(PluginTargetDisplay.resolve(plugin).kind, .unavailable)
    }

}
