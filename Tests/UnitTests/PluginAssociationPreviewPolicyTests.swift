import XCTest
@testable import FilterKit

final class PluginAssociationPreviewPolicyTests: XCTestCase {
    private func item(ownership: PluginOwnership = .filterKit,
                      pairing: PluginPairingState = .paired,
                      permission: PluginManagementPermission? = PluginManagementPermission(access: .manageable, reasonKey: "test"),
                      hardBound: String? = "com.example.hard") -> PluginScanItem {
        PluginScanItem(id: "plugin", baseName: "Example", dylibFileName: "Example.dylib",
                       plistFileName: "Example.plist", manifestFileName: "Example.fk.json",
                       pairingState: pairing, binaryKind: .machO, ownership: ownership,
                       filterKitPluginID: nil, packageIdentifier: nil, dylibSHA256: nil,
                       plistSHA256: nil, hardBoundBundleIdentifier: hardBound,
                       softAssociatedBundleIdentifiers: [], warnings: [], filterConfiguration: nil,
                       managementPermission: permission)
    }

    func testThirdPartyPluginIsNeverEligible() {
        let result = PluginAssociationPreviewPolicy().evaluate(
            plugin: item(ownership: .packageManager), targetBundleIdentifier: "com.example.target",
            installedBundleIdentifiers: ["com.example.target"], originalPlistIsReadable: true)
        XCTAssertFalse(result.isEligible)
        XCTAssertTrue(result.blockers.contains(.thirdPartyPlugin))
    }

    func testHardBoundAppIsImmutable() {
        let result = PluginAssociationPreviewPolicy().evaluate(
            plugin: item(hardBound: "com.example.target"), targetBundleIdentifier: "com.example.target",
            installedBundleIdentifiers: ["com.example.target"], originalPlistIsReadable: true)
        XCTAssertTrue(result.blockers.contains(.hardBoundAppIsImmutable))
    }

    func testBundleIdentifierIdentityIsCaseInsensitive() {
        let result = PluginAssociationPreviewPolicy().evaluate(
            plugin: item(hardBound: "com.example.target"), targetBundleIdentifier: "COM.EXAMPLE.TARGET",
            installedBundleIdentifiers: ["com.example.target"], originalPlistIsReadable: true)
        XCTAssertTrue(result.blockers.contains(.hardBoundAppIsImmutable))
        XCTAssertFalse(result.blockers.contains(.targetAppUnavailable))
    }

    func testMissingAppOrUnreadablePlistBlocksPreview() {
        let result = PluginAssociationPreviewPolicy().evaluate(
            plugin: item(), targetBundleIdentifier: "com.example.target",
            installedBundleIdentifiers: [], originalPlistIsReadable: false)
        XCTAssertTrue(result.blockers.contains(.targetAppUnavailable))
        XCTAssertTrue(result.blockers.contains(.originalPlistUnavailable))
    }
}
