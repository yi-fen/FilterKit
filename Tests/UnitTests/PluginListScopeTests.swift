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

    func testFilterKitScopeRequiresVerifiedHelperAttestationForUnknownOwnership() {
        XCTAssertTrue(PluginListScope.includes(item(ownership: .filterKit), filterKitOnly: true))
        XCTAssertFalse(PluginListScope.includes(item(ownership: .unknown, pluginID: "untrusted-hint"), filterKitOnly: true))
        XCTAssertTrue(PluginListScope.includes(helperAttestedItem(), filterKitOnly: true))
        XCTAssertFalse(PluginListScope.includes(item(ownership: .unknown), filterKitOnly: true))
        XCTAssertFalse(PluginListScope.includes(item(ownership: .packageManager), filterKitOnly: true))
    }

    private func helperAttestedItem() -> PluginScanItem {
        var value = PluginScanItem(id: "sample.dylib", baseName: "sample", dylibFileName: "sample.dylib",
            plistFileName: "sample.plist", manifestFileName: "sample.fk.json", pairingState: .paired,
            binaryKind: .machO, ownership: .unknown, filterKitPluginID: "00000000-0000-0000-0000-000000000001",
            packageIdentifier: nil, dylibSHA256: String(repeating: "a", count: 64),
            plistSHA256: String(repeating: "b", count: 64), hardBoundBundleIdentifier: "com.example.app",
            softAssociatedBundleIdentifiers: [], warnings: [],
            filterConfiguration: PluginFilterConfiguration(parseState: .valid, containerKey: "Filter",
                bundles: ["com.example.app"], executables: [], classes: [], modeDescription: nil,
                unknownKeys: [], warnings: []), managementPermission: PluginManagementPermission(
                    access: .readOnlyUnknownSource, reasonKey: "test"))
        value.helperIdentityAttestation = HelperPluginIdentityAttestation(requestID: UUID(), status: .verified,
            reasonCode: "test", pluginID: UUID(uuidString: "00000000-0000-0000-0000-000000000001"),
            dylibFileName: "sample.dylib", plistFileName: "sample.plist",
            dylibSHA256: String(repeating: "a", count: 64), plistSHA256: String(repeating: "b", count: 64),
            manifestSHA256: String(repeating: "c", count: 64), machOIdentitySHA256: String(repeating: "d", count: 64),
            hardBoundBundleIdentifier: "com.example.app", softAssociations: [],
            filterConfiguration: value.filterConfiguration, completedAt: Date())
        return value
    }
}
