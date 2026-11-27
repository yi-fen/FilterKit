import Foundation

enum PluginOwnership { case filterKit, packageManager, unknown }
enum PluginPairingState { case paired, orphanDylib, orphanPlist, unreadable, invalid }
enum PluginBinaryKind { case machO, unsupportedOrUnknown, notMachO }
enum PluginIdentityStatus { case unique, duplicateIdentity, installNameCollision, uuidCDHashMismatch, insufficientFingerprint, unresolvedBasenameCollision }
enum PluginOwnershipConflict { case none, filterKitVsPackageManager, multiplePackageOwners }
enum PluginManifestIdentityBinding { case notPresent, fileHashesOnly, binaryIdentityVerified, unverified }
enum PluginFilterParseState { case valid, partial, invalid, unavailable }

struct PluginFilterConfiguration {
    let parseState: PluginFilterParseState
    let bundles: [String]
    let executables: [String]
    let classes: [String]
}
struct FilterKitManifestSoftAssociation {
    let bundleIdentifier: String
    let isEnabled: Bool
}
struct PluginManagementPermission {
    let canModify: Bool
}
struct PluginScanItem {
    let id: String
    let baseName: String
    let ownership: PluginOwnership
    let pairingState: PluginPairingState
    let binaryKind: PluginBinaryKind?
    let identityStatus: PluginIdentityStatus
    let ownershipConflict: PluginOwnershipConflict
    let manifestIdentityBinding: PluginManifestIdentityBinding
    let managementPermission: PluginManagementPermission?
    let hardBoundBundleIdentifier: String?
    let softAssociatedBundleIdentifiers: [String]
    let softAssociationStates: [FilterKitManifestSoftAssociation]?
    let filterConfiguration: PluginFilterConfiguration?
    let filterKitPluginID: String?
    let dylibSHA256: String?
    let plistSHA256: String?
}
