import Foundation

private let pluginID = "00000000-0000-0000-0000-000000000001"
private let permission = PluginManagementPermission(access: .manageable, reasonKey: "host")

private func makePlugin(hardBound: String, soft: [FilterKitManifestSoftAssociation],
                        bundles: [String], ownership: PluginOwnership = .filterKit) -> PluginScanItem {
    let filter = PluginFilterConfiguration(parseState: .valid, containerKey: "Filter",
        bundles: bundles, executables: [], classes: [], modeDescription: nil,
        unknownKeys: [], warnings: [])
    var item = PluginScanItem(id: "Example.dylib", baseName: "Example",
        dylibFileName: "Example.dylib", plistFileName: "Example.plist",
        manifestFileName: "Example.fk.json", pairingState: .paired, binaryKind: .machO,
        ownership: ownership, filterKitPluginID: pluginID, packageIdentifier: nil,
        dylibSHA256: String(repeating: "a", count: 64), plistSHA256: String(repeating: "b", count: 64),
        hardBoundBundleIdentifier: hardBound, softAssociatedBundleIdentifiers: soft.map(\.bundleIdentifier),
        warnings: [], filterConfiguration: filter, managementPermission: permission,
        identityStatus: .unique, ownershipConflict: .none, manifestIdentityBinding: .binaryIdentityVerified,
        manifestSHA256: String(repeating: "c", count: 64), softAssociationStates: soft)
    item.identityFingerprint = String(repeating: "d", count: 64)
    if ownership == .filterKit {
        item.helperIdentityAttestation = HelperPluginIdentityAttestation(
            requestID: UUID(), status: .verified, reasonCode: "host_verified",
            pluginID: UUID(uuidString: pluginID), dylibFileName: "Example.dylib", plistFileName: "Example.plist",
            dylibSHA256: item.dylibSHA256, plistSHA256: item.plistSHA256,
            manifestSHA256: item.manifestSHA256, machOIdentitySHA256: item.identityFingerprint,
            hardBoundBundleIdentifier: hardBound, softAssociations: soft,
            filterConfiguration: filter, completedAt: Date())
    }
    return item
}

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fputs("FAIL \(message)\n", stderr); exit(1) }
    print("PASS \(message)")
}

@main
struct P237R3ActivationConsistencySmoke {
    static func main() {
        let resolver = AppPluginActivationStateResolver()
        let hardBound = makePlugin(hardBound: "com.example.source", soft: [], bundles: [])
        let hardState = resolver.resolve(plugin: hardBound, targetBundleIdentifier: "com.example.source")!
        check(hardState.isHardBound && hardState.observedState == .disabled && hardState.canPreviewToggle,
              "hard-bound association remains permanent while activation can be preview-disabled")

        let soft = [
            FilterKitManifestSoftAssociation(bundleIdentifier: "com.example.one", isEnabled: true),
            FilterKitManifestSoftAssociation(bundleIdentifier: "com.example.two", isEnabled: false)
        ]
        let multi = makePlugin(hardBound: "com.example.source", soft: soft,
            bundles: ["com.example.source", "com.example.one"])
        let one = resolver.resolve(plugin: multi, targetBundleIdentifier: "com.example.one")!
        let two = resolver.resolve(plugin: multi, targetBundleIdentifier: "com.example.two")!
        check(one.observedState == .enabled && two.observedState == .disabled,
              "multi-App soft-association states remain independent")
        check(one.canPreviewToggle && two.canPreviewToggle && one.id != two.id,
              "each eligible App receives an independent preview identity")

        let expired = resolver.resolve(plugin: multi, targetBundleIdentifier: "com.example.one",
            now: Date().addingTimeInterval(HelperPluginIdentityAttestation.maximumAge + 1))!
        check(!expired.canPreviewToggle && expired.readOnlyReasonKey == "apps.detail.activation_helper_attestation_expired",
              "expired Helper attestation automatically locks preview")

        var changedManifest = multi
        changedManifest.manifestSHA256 = String(repeating: "e", count: 64)
        let changed = resolver.resolve(plugin: changedManifest, targetBundleIdentifier: "com.example.one")!
        check(!changed.canPreviewToggle, "manifest byte hash change invalidates Helper identity evidence")

        let badFilter = makePlugin(hardBound: "com.example.source", soft: soft,
            bundles: ["com.example.source", "com.example.one", "com.example.two"])
        let badOne = resolver.resolve(plugin: badFilter, targetBundleIdentifier: "com.example.one")!
        let badTwo = resolver.resolve(plugin: badFilter, targetBundleIdentifier: "com.example.two")!
        check(!badOne.canPreviewToggle && !badTwo.canPreviewToggle,
              "disabled soft association present in Filter locks every affected App")

        let thirdParty = makePlugin(hardBound: "com.example.source", soft: [],
            bundles: ["com.example.source"], ownership: .packageManager)
        let thirdPartyState = resolver.resolve(plugin: thirdParty, targetBundleIdentifier: "com.example.source")!
        check(!thirdPartyState.canPreviewToggle
              && PluginIdentityVerificationResolver().resolve(plugin: thirdParty).status == .rejected,
              "third-party plugin remains rejected and read-only")

        var scannerUnknown = makePlugin(hardBound: "com.example.source", soft: [], bundles: ["com.example.source"], ownership: .unknown)
        check(!resolver.resolve(plugin: scannerUnknown, targetBundleIdentifier: "com.example.source")!.canPreviewToggle,
              "unknown scanner ownership is locked without Helper proof")
        scannerUnknown.helperIdentityAttestation = makePlugin(hardBound: "com.example.source", soft: [], bundles: ["com.example.source"]).helperIdentityAttestation
        check(resolver.resolve(plugin: scannerUnknown, targetBundleIdentifier: "com.example.source")!.canPreviewToggle,
              "unknown scanner ownership requires and accepts verified Helper proof")

        var ledger = AppPluginActivationPreviewLedger()
        ledger.setPreview(true, pluginID: "plugin", targetBundleIdentifier: "com.example.one", snapshotID: "scan-1")
        ledger.setPreview(false, pluginID: "plugin", targetBundleIdentifier: "com.example.two", snapshotID: "scan-1")
        check(ledger.preview(pluginID: "plugin", targetBundleIdentifier: "com.example.one") == true
              && ledger.preview(pluginID: "plugin", targetBundleIdentifier: "com.example.two") == false,
              "preview ledger isolates the same plugin across Apps")
        ledger.updateSnapshot("scan-2")
        check(ledger.preview(pluginID: "plugin", targetBundleIdentifier: "com.example.one") == nil,
              "new scan snapshot clears stale previews")
        print("RESULT 11/11 passed")
    }
}
