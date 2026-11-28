import XCTest
@testable import FilterKit

final class AppPluginActivationStateResolverTests: XCTestCase {
    private let resolver = AppPluginActivationStateResolver()
    private let permission = PluginManagementPermission(access: .manageable, reasonKey: "test")

    func testHardBoundAppCanBeTurnedOffWithoutChangingBinding() throws {
        let plugin = makePlugin(hardBound: "com.example.source", bundles: [])
        let state = try XCTUnwrap(resolver.resolve(plugin: plugin, targetBundleIdentifier: "com.example.source"))
        XCTAssertEqual(state.associationKind, .hardBound)
        XCTAssertEqual(state.observedState, .disabled)
        XCTAssertTrue(state.isHardBound)
        XCTAssertTrue(state.canPreviewToggle)
        XCTAssertEqual(plugin.hardBoundBundleIdentifier, "com.example.source")
    }

    func testBundleIdentifierMatchingIsCaseInsensitiveAcrossOwnerAssociationAndFilter() throws {
        let ownerPlugin = makePlugin(hardBound: "com.example.source", bundles: ["COM.EXAMPLE.SOURCE"])
        let owner = try XCTUnwrap(resolver.resolve(plugin: ownerPlugin, targetBundleIdentifier: "COM.EXAMPLE.SOURCE"))
        XCTAssertEqual(owner.associationKind, .hardBound)
        XCTAssertEqual(owner.observedState, .enabled)

        let associatedPlugin = makePlugin(hardBound: "com.example.source",
            soft: ["com.example.target"], softStates: [
                FilterKitManifestSoftAssociation(bundleIdentifier: "com.example.target", isEnabled: true)
            ], bundles: ["com.example.source", "COM.EXAMPLE.TARGET"])
        let associated = try XCTUnwrap(resolver.resolve(plugin: associatedPlugin,
            targetBundleIdentifier: "Com.Example.Target"))
        XCTAssertEqual(associated.associationKind, .softAssociated)
        XCTAssertEqual(associated.observedState, .enabled)
        XCTAssertEqual(associated.crossCheck, .matched)
    }

    func testSoftAssociationUsesManifestAndFilterCrossCheck() throws {
        let matching = makePlugin(hardBound: "com.example.source", soft: ["com.example.target"], softStates: [
            FilterKitManifestSoftAssociation(bundleIdentifier: "com.example.target", isEnabled: true)
        ], bundles: ["com.example.source", "com.example.target"])
        let state = try XCTUnwrap(resolver.resolve(plugin: matching, targetBundleIdentifier: "com.example.target"))
        XCTAssertEqual(state.associationKind, .softAssociated)
        XCTAssertEqual(state.observedState, .enabled)
        XCTAssertEqual(state.crossCheck, .matched)
        XCTAssertTrue(state.canPreviewToggle)

        let mismatch = makePlugin(hardBound: "com.example.source", soft: ["com.example.target"], softStates: [
            FilterKitManifestSoftAssociation(bundleIdentifier: "com.example.target", isEnabled: false)
        ], bundles: ["com.example.source", "com.example.target"])
        let mismatchState = try XCTUnwrap(resolver.resolve(plugin: mismatch, targetBundleIdentifier: "com.example.target"))
        XCTAssertEqual(mismatchState.observedState, .inconsistent)
        XCTAssertEqual(mismatchState.crossCheck, .manifestFilterMismatch)
        XCTAssertFalse(mismatchState.canPreviewToggle)
    }

    func testSamePluginHasIndependentPerAppObservedState() throws {
        let plugin = makePlugin(
            hardBound: "com.example.source",
            soft: ["com.example.one", "com.example.two"],
            softStates: [
                FilterKitManifestSoftAssociation(bundleIdentifier: "com.example.one", isEnabled: true),
                FilterKitManifestSoftAssociation(bundleIdentifier: "com.example.two", isEnabled: false)
            ],
            bundles: ["com.example.source", "com.example.one"])
        let one = try XCTUnwrap(resolver.resolve(plugin: plugin, targetBundleIdentifier: "com.example.one"))
        let two = try XCTUnwrap(resolver.resolve(plugin: plugin, targetBundleIdentifier: "com.example.two"))
        XCTAssertEqual(one.observedState, .enabled)
        XCTAssertEqual(two.observedState, .disabled)
        XCTAssertNotEqual(one.observedState, two.observedState)
        XCTAssertNotEqual(one.id, two.id, "Identifiable keys must include the target App")
    }

    func testThirdPartyAndUnknownPluginsNeverGetToggle() throws {
        let thirdParty = makePlugin(ownership: .packageManager, hardBound: "com.example.target", bundles: ["com.example.target"])
        let thirdPartyState = try XCTUnwrap(resolver.resolve(plugin: thirdParty, targetBundleIdentifier: "com.example.target"))
        XCTAssertFalse(thirdPartyState.canPreviewToggle)
        XCTAssertEqual(PluginIdentityVerificationResolver().resolve(plugin: thirdParty).status, .rejected)

        let unknown = makePlugin(ownership: .unknown, hardBound: "com.example.target", bundles: ["com.example.target"])
        let unknownState = try XCTUnwrap(resolver.resolve(plugin: unknown, targetBundleIdentifier: "com.example.target"))
        XCTAssertFalse(unknownState.canPreviewToggle)
    }

    func testUnknownScannerOwnershipCanBePromotedOnlyByHelperProof() throws {
        var unknown = makePlugin(ownership: .unknown, hardBound: "com.example.target", bundles: ["com.example.target"])
        XCTAssertNil(unknown.helperIdentityAttestation)
        XCTAssertFalse(try XCTUnwrap(resolver.resolve(plugin: unknown,
            targetBundleIdentifier: "com.example.target")).canPreviewToggle)

        let verifiedSource = makePlugin(hardBound: "com.example.target", bundles: ["com.example.target"])
        unknown.identityFingerprint = verifiedSource.identityFingerprint
        unknown.helperIdentityAttestation = verifiedSource.helperIdentityAttestation
        let state = try XCTUnwrap(resolver.resolve(plugin: unknown, targetBundleIdentifier: "com.example.target"))
        XCTAssertTrue(state.canPreviewToggle, "Helper root-owned package/manifest proof is the ownership authority")
    }

    func testAlternateMatchDimensionsCannotBeAttributedToSingleApp() throws {
        let filter = PluginFilterConfiguration(parseState: .valid, containerKey: "Filter",
            bundles: ["com.example.target"], executables: ["Target"], classes: [],
            modeDescription: nil, unknownKeys: [], warnings: [])
        var plugin = makePlugin(hardBound: "com.example.target", bundles: ["com.example.target"])
        plugin = PluginScanItem(
            id: plugin.id, baseName: plugin.baseName, dylibFileName: plugin.dylibFileName,
            plistFileName: plugin.plistFileName, manifestFileName: plugin.manifestFileName,
            pairingState: plugin.pairingState, binaryKind: plugin.binaryKind, ownership: plugin.ownership,
            filterKitPluginID: plugin.filterKitPluginID, packageIdentifier: plugin.packageIdentifier,
            dylibSHA256: plugin.dylibSHA256, plistSHA256: plugin.plistSHA256,
            hardBoundBundleIdentifier: plugin.hardBoundBundleIdentifier,
            softAssociatedBundleIdentifiers: plugin.softAssociatedBundleIdentifiers,
            warnings: plugin.warnings, filterConfiguration: filter, managementPermission: plugin.managementPermission,
            identityStatus: plugin.identityStatus, ownershipConflict: plugin.ownershipConflict,
            manifestIdentityBinding: plugin.manifestIdentityBinding, softAssociationStates: plugin.softAssociationStates)
        let state = try XCTUnwrap(resolver.resolve(plugin: plugin, targetBundleIdentifier: "com.example.target"))
        XCTAssertEqual(state.observedState, .ambiguousFilter)
        XCTAssertFalse(state.canPreviewToggle)
    }

    func testGlobalFilterAndMissingManifestStateAreLocked() throws {
        let global = makePlugin(hardBound: "com.example.target", bundles: ["*"])
        let globalState = try XCTUnwrap(resolver.resolve(plugin: global, targetBundleIdentifier: "com.example.target"))
        XCTAssertEqual(globalState.observedState, .globalFilter)
        XCTAssertFalse(globalState.canPreviewToggle)

        let missingState = makePlugin(hardBound: "com.example.source", soft: ["com.example.target"], softStates: [], bundles: ["com.example.source", "com.example.target"])
        let missing = try XCTUnwrap(resolver.resolve(plugin: missingState, targetBundleIdentifier: "com.example.target"))
        XCTAssertEqual(missing.crossCheck, .manifestStateMissing)
        XCTAssertFalse(missing.canPreviewToggle)
    }


    func testProductionScannerEvidenceRemainsLockedUntilVerified() throws {
        var plugin = makePlugin(hardBound: "com.example.target", bundles: ["com.example.target"])
        plugin.manifestIdentityBinding = .unverified
        plugin.helperIdentityAttestation = nil
        let evidence = PluginIdentityVerificationResolver().resolve(plugin: plugin)
        XCTAssertEqual(evidence.status, .unverified)
        let state = try XCTUnwrap(resolver.resolve(plugin: plugin, targetBundleIdentifier: "com.example.target"))
        XCTAssertFalse(state.canPreviewToggle)
    }

    func testHelperAttestationMismatchKeepsPluginReadOnly() throws {
        var plugin = makePlugin(hardBound: "com.example.target", bundles: ["com.example.target"])
        let original = try XCTUnwrap(plugin.helperIdentityAttestation)
        plugin.helperIdentityAttestation = HelperPluginIdentityAttestation(
            requestID: original.requestID, status: .verified, reasonCode: original.reasonCode,
            pluginID: original.pluginID, dylibFileName: original.dylibFileName,
            plistFileName: original.plistFileName, dylibSHA256: String(repeating: "e", count: 64),
            plistSHA256: original.plistSHA256, manifestSHA256: original.manifestSHA256,
            machOIdentitySHA256: original.machOIdentitySHA256,
            hardBoundBundleIdentifier: original.hardBoundBundleIdentifier,
            softAssociations: original.softAssociations, filterConfiguration: original.filterConfiguration,
            completedAt: original.completedAt)
        let evidence = PluginIdentityVerificationResolver().resolve(plugin: plugin)
        XCTAssertEqual(evidence.status, .unverified)
        let state = try XCTUnwrap(resolver.resolve(plugin: plugin, targetBundleIdentifier: "com.example.target"))
        XCTAssertFalse(state.canPreviewToggle)
    }

    func testIdentityCollisionIsRejected() {
        var plugin = makePlugin(hardBound: "com.example.target", bundles: ["com.example.target"])
        plugin.identityStatus = .uuidCDHashMismatch
        let evidence = PluginIdentityVerificationResolver().resolve(plugin: plugin)
        XCTAssertEqual(evidence.status, .rejected)
        XCTAssertFalse(evidence.permitsActivationPreview)
    }

    func testPreviewLedgerSeparatesAppsAndClearsOnRefresh() {
        var ledger = AppPluginActivationPreviewLedger()
        ledger.setPreview(true, pluginID: "plugin-A", targetBundleIdentifier: "com.example.one", snapshotID: "scan-1")
        ledger.setPreview(false, pluginID: "plugin-A", targetBundleIdentifier: "com.example.two", snapshotID: "scan-1")
        XCTAssertEqual(ledger.preview(pluginID: "plugin-A", targetBundleIdentifier: "com.example.one"), true)
        XCTAssertEqual(ledger.preview(pluginID: "plugin-A", targetBundleIdentifier: "com.example.two"), false)
        ledger.updateSnapshot("scan-2")
        XCTAssertNil(ledger.preview(pluginID: "plugin-A", targetBundleIdentifier: "com.example.one"))
        XCTAssertNil(ledger.preview(pluginID: "plugin-A", targetBundleIdentifier: "com.example.two"))
    }


    func testSupersededScanGenerationCannotPublish() {
        var tracker = PluginScanGenerationTracker()
        let first = tracker.begin()
        let second = tracker.begin()
        XCTAssertFalse(tracker.isCurrent(first))
        XCTAssertTrue(tracker.isCurrent(second))
    }

    func testExpiredHelperAttestationLocksPreview() throws {
        let plugin = makePlugin(hardBound: "com.example.target", bundles: ["com.example.target"])
        let now = Date()
        let fresh = PluginIdentityVerificationResolver().resolve(plugin: plugin, now: now)
        XCTAssertEqual(fresh.status, .verified)
        let expired = PluginIdentityVerificationResolver().resolve(plugin: plugin,
            now: now.addingTimeInterval(HelperPluginIdentityAttestation.maximumAge + 1))
        XCTAssertEqual(expired.status, .unverified)
        let state = try XCTUnwrap(resolver.resolve(plugin: plugin,
            targetBundleIdentifier: "com.example.target",
            now: now.addingTimeInterval(HelperPluginIdentityAttestation.maximumAge + 1)))
        XCTAssertFalse(state.canPreviewToggle)
    }

    func testManifestHashChangeInvalidatesHelperEvidence() {
        var plugin = makePlugin(hardBound: "com.example.target", bundles: ["com.example.target"])
        plugin.manifestSHA256 = String(repeating: "f", count: 64)
        let evidence = PluginIdentityVerificationResolver().resolve(plugin: plugin)
        XCTAssertEqual(evidence.status, .unverified)
    }

    func testSoftAssociationSetMustMatchFilterForEveryApp() throws {
        let plugin = makePlugin(hardBound: "com.example.source",
            soft: ["com.example.one", "com.example.two"],
            softStates: [
                FilterKitManifestSoftAssociation(bundleIdentifier: "com.example.one", isEnabled: true),
                FilterKitManifestSoftAssociation(bundleIdentifier: "com.example.two", isEnabled: false)
            ], bundles: ["com.example.source", "com.example.one"])
        XCTAssertEqual(PluginIdentityVerificationResolver().resolve(plugin: plugin).status, .verified)

        let changed = makePlugin(hardBound: "com.example.source",
            soft: ["com.example.one", "com.example.two"],
            softStates: [
                FilterKitManifestSoftAssociation(bundleIdentifier: "com.example.one", isEnabled: true),
                FilterKitManifestSoftAssociation(bundleIdentifier: "com.example.two", isEnabled: false)
            ], bundles: ["com.example.source", "com.example.one", "com.example.two"])
        XCTAssertEqual(PluginIdentityVerificationResolver().resolve(plugin: changed).status, .unverified)
        let one = try XCTUnwrap(resolver.resolve(plugin: changed, targetBundleIdentifier: "com.example.one"))
        let two = try XCTUnwrap(resolver.resolve(plugin: changed, targetBundleIdentifier: "com.example.two"))
        XCTAssertFalse(one.canPreviewToggle)
        XCTAssertFalse(two.canPreviewToggle)
    }

    private func makePlugin(ownership: PluginOwnership = .filterKit,
                            hardBound: String? = nil,
                            soft: [String] = [],
                            softStates: [FilterKitManifestSoftAssociation] = [],
                            bundles: [String]) -> PluginScanItem {
        let filter = PluginFilterConfiguration(parseState: .valid, containerKey: "Filter",
            bundles: bundles, executables: [], classes: [], modeDescription: nil,
            unknownKeys: [], warnings: [])
        var plugin = PluginScanItem(
            id: "example.dylib", baseName: "Example", dylibFileName: "Example.dylib",
            plistFileName: "Example.plist", manifestFileName: "Example.fk.json",
            pairingState: .paired, binaryKind: .machO, ownership: ownership,
            filterKitPluginID: "00000000-0000-0000-0000-000000000001", packageIdentifier: nil,
            dylibSHA256: String(repeating: "a", count: 64), plistSHA256: String(repeating: "b", count: 64),
            hardBoundBundleIdentifier: hardBound, softAssociatedBundleIdentifiers: soft,
            warnings: [], filterConfiguration: filter, managementPermission: permission,
            identityStatus: .unique, ownershipConflict: .none,
            manifestIdentityBinding: .binaryIdentityVerified, manifestSHA256: String(repeating: "c", count: 64),
            softAssociationStates: softStates)
        if ownership == .filterKit, let hardBound {
            plugin.identityFingerprint = String(repeating: "d", count: 64)
            plugin.helperIdentityAttestation = HelperPluginIdentityAttestation(
                requestID: UUID(), status: .verified, reasonCode: "test_verified",
                pluginID: UUID(uuidString: "00000000-0000-0000-0000-000000000001"),
                dylibFileName: "Example.dylib", plistFileName: "Example.plist",
                dylibSHA256: plugin.dylibSHA256, plistSHA256: plugin.plistSHA256,
                manifestSHA256: plugin.manifestSHA256,
                machOIdentitySHA256: String(repeating: "d", count: 64),
                hardBoundBundleIdentifier: hardBound, softAssociations: softStates,
                filterConfiguration: filter, completedAt: Date())
        }
        return plugin
    }
}
