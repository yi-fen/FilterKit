import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
let resolver = AppPluginActivationStateResolver()
let permission = PluginManagementPermission(canModify: true)
func plugin(ownership: PluginOwnership = .filterKit, hard: String? = nil,
            soft: [String] = [], states: [FilterKitManifestSoftAssociation] = [],
            bundles: [String]) -> PluginScanItem {
    PluginScanItem(id: "p", baseName: "Plugin", ownership: ownership, pairingState: .paired,
        binaryKind: .machO, identityStatus: .unique, ownershipConflict: .none,
        manifestIdentityBinding: .binaryIdentityVerified, managementPermission: permission,
        hardBoundBundleIdentifier: hard, softAssociatedBundleIdentifiers: soft,
        softAssociationStates: states,
        filterConfiguration: PluginFilterConfiguration(parseState: .valid, bundles: bundles,
            executables: [], classes: []), filterKitPluginID: "00000000-0000-0000-0000-000000000001",
        dylibSHA256: String(repeating: "a", count: 64), plistSHA256: String(repeating: "b", count: 64))
}
let hard = resolver.resolve(plugin: plugin(hard: "com.example.hard", bundles: []),
                            targetBundleIdentifier: "com.example.hard")!
expect(hard.isHardBound && hard.observedState == .disabled && hard.canPreviewToggle,
       "hard-bound app may preview disable without unbinding")
let soft = resolver.resolve(plugin: plugin(soft: ["com.example.one", "com.example.two"],
    states: [.init(bundleIdentifier: "com.example.one", isEnabled: true),
             .init(bundleIdentifier: "com.example.two", isEnabled: false)],
    bundles: ["com.example.one"]), targetBundleIdentifier: "com.example.one")!
let softTwo = resolver.resolve(plugin: plugin(soft: ["com.example.one", "com.example.two"],
    states: [.init(bundleIdentifier: "com.example.one", isEnabled: true),
             .init(bundleIdentifier: "com.example.two", isEnabled: false)],
    bundles: ["com.example.one"]), targetBundleIdentifier: "com.example.two")!
expect(soft.observedState == .enabled && softTwo.observedState == .disabled,
       "same plugin state is isolated per target app")
let mismatch = resolver.resolve(plugin: plugin(soft: ["com.example.one"],
    states: [.init(bundleIdentifier: "com.example.one", isEnabled: false)],
    bundles: ["com.example.one"]), targetBundleIdentifier: "com.example.one")!
expect(mismatch.observedState == .inconsistent && !mismatch.canPreviewToggle,
       "manifest/filter mismatch must lock toggle")
let thirdParty = resolver.resolve(plugin: plugin(ownership: .packageManager,
    hard: "com.example.hard", bundles: ["com.example.hard"]),
    targetBundleIdentifier: "com.example.hard")!
expect(!thirdParty.canPreviewToggle, "third-party plugin must remain read-only")
let unverified = plugin(hard: "com.example.unverified", bundles: [])
// The fixture above carries valid evidence; remove the verified binding to model the
// production read-only scanner, which deliberately reports ownership as unknown.
let productionLike = PluginScanItem(id: unverified.id, baseName: unverified.baseName,
    ownership: .unknown, pairingState: unverified.pairingState, binaryKind: unverified.binaryKind,
    identityStatus: unverified.identityStatus, ownershipConflict: unverified.ownershipConflict,
    manifestIdentityBinding: .unverified, managementPermission: unverified.managementPermission,
    hardBoundBundleIdentifier: unverified.hardBoundBundleIdentifier,
    softAssociatedBundleIdentifiers: unverified.softAssociatedBundleIdentifiers,
    softAssociationStates: unverified.softAssociationStates, filterConfiguration: unverified.filterConfiguration,
    filterKitPluginID: unverified.filterKitPluginID, dylibSHA256: unverified.dylibSHA256,
    plistSHA256: unverified.plistSHA256)
let locked = resolver.resolve(plugin: productionLike, targetBundleIdentifier: "com.example.unverified")!
expect(!locked.canPreviewToggle, "unverified production scan remains locked")

var ledger = AppPluginActivationPreviewLedger()
ledger.setPreview(true, pluginID: "p", targetBundleIdentifier: "com.example.one", snapshotID: "1")
ledger.setPreview(false, pluginID: "p", targetBundleIdentifier: "com.example.two", snapshotID: "1")
expect(ledger.preview(pluginID: "p", targetBundleIdentifier: "com.example.one") == true
    && ledger.preview(pluginID: "p", targetBundleIdentifier: "com.example.two") == false,
    "preview values are isolated by target App")
ledger.updateSnapshot("2")
expect(ledger.preview(pluginID: "p", targetBundleIdentifier: "com.example.one") == nil,
       "new scan snapshot clears stale previews")
var generations = PluginScanGenerationTracker()
let oldGeneration = generations.begin()
let newGeneration = generations.begin()
expect(!generations.isCurrent(oldGeneration) && generations.isCurrent(newGeneration),
       "superseded scan completion is rejected")
print("P2-37-R1 activation model smoke: 8/8 passed")
