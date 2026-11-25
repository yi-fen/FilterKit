import XCTest
@testable import FilterKit

final class PluginListScopeTests: XCTestCase {
    private func item(ownership: PluginOwnership, pluginID: String? = nil) -> PluginScanItem {
        PluginScanItem(id: "sample.dylib", baseName: "sample", dylibFileName: "sample.dylib",
            plistFileName: nil, manifestFileName: nil, pairingState: .orphanDylib,
            binaryKind: nil, ownership: ownership, filterKitPluginID: pluginID,
            packageIdentifier: nil, dylibSHA256: nil, plistSHA256: nil,
            hardBoundBundleIdentifier: nil, softAssociatedBundleIdentifiers: [], warnings: [],
            filterConfiguration: nil, managementPermission: PluginManagementPermission(
                access: .readOnlyUnknownSource, reasonKey: "test"))
    }

    func testDefaultInventoryShowsUnverifiedAndPackageOwnedPlugins() {
        XCTAssertTrue(PluginListScope.includes(item(ownership: .unknown), filterKitOnly: false))
        XCTAssertTrue(PluginListScope.includes(item(ownership: .packageManager), filterKitOnly: false))
    }

    func testFilterKitScopeDoesNotConfuseCanModifyWithOwnership() {
        XCTAssertTrue(PluginListScope.includes(item(ownership: .filterKit), filterKitOnly: true))
        XCTAssertTrue(PluginListScope.includes(item(ownership: .unknown, pluginID: "verified-id"), filterKitOnly: true))
        XCTAssertFalse(PluginListScope.includes(item(ownership: .unknown), filterKitOnly: true))
        XCTAssertFalse(PluginListScope.includes(item(ownership: .packageManager), filterKitOnly: true))
    }
}
