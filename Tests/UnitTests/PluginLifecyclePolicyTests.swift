import XCTest
@testable import FilterKit

final class PluginLifecyclePolicyTests: XCTestCase {
    private func evidence(enabled: Set<String> = [], installed: Set<String> = ["com.example.owner", "com.example.extra"],
                          ownership: PluginOwnership = .filterKit,
                          payload: PluginLifecycleEvidence.PayloadState = .verifiedPair,
                          manifestVerified: Bool = true) -> PluginLifecycleEvidence {
        PluginLifecycleEvidence(ownership: ownership, payloadState: payload,
            manifestVerified: manifestVerified, fixedOwnerBundleIdentifier: "com.example.owner",
            additionalAssociationBundleIdentifiers: ["com.example.extra"],
            enabledBundleIdentifiers: enabled, installedBundleIdentifiers: installed)
    }

    func testAPPIsOnlyEntryPointForInjectAndActivation() {
        for action in [PluginLifecycleAction.inject, .enable, .disable] {
            XCTAssertNil(PluginLifecyclePolicy.denial(for: action, entryPoint: .apps, evidence: evidence()))
            XCTAssertEqual(PluginLifecyclePolicy.denial(for: action, entryPoint: .plugin, evidence: evidence()), .wrongEntryPoint)
        }
    }

    func testPluginIsOnlyEntryPointForUninstallExportRestoreAndAssociations() {
        for action in [PluginLifecycleAction.uninstall, .export, .restore] {
            XCTAssertNil(PluginLifecyclePolicy.denial(for: action, entryPoint: .plugin, evidence: evidence()))
            XCTAssertEqual(PluginLifecyclePolicy.denial(for: action, entryPoint: .apps, evidence: evidence()), .wrongEntryPoint)
        }
        XCTAssertNil(PluginLifecyclePolicy.denial(for: .addAssociation, entryPoint: .plugin,
            evidence: evidence(), associationBundleIdentifier: "com.example.new"))
        XCTAssertEqual(PluginLifecyclePolicy.denial(for: .addAssociation, entryPoint: .apps,
            evidence: evidence(), associationBundleIdentifier: "com.example.new"), .wrongEntryPoint)
        XCTAssertNil(PluginLifecyclePolicy.denial(for: .removeAssociation, entryPoint: .plugin,
            evidence: evidence(), associationBundleIdentifier: "com.example.extra"))
        XCTAssertEqual(PluginLifecyclePolicy.denial(for: .removeAssociation, entryPoint: .apps,
            evidence: evidence(), associationBundleIdentifier: "com.example.extra"), .wrongEntryPoint)
    }

    func testUninstallRemovesPluginForAllAssociatedAppsEvenWhenConfiguredEnabled() {
        XCTAssertNil(PluginLifecyclePolicy.denial(for: .uninstall, entryPoint: .plugin,
            evidence: evidence(enabled: ["com.example.owner", "com.example.extra"])))
    }

    func testExternalOrUnknownPluginsCannotBeManaged() {
        for ownership in [PluginOwnership.packageManager, .unknown] {
            XCTAssertEqual(PluginLifecyclePolicy.denial(for: .uninstall, entryPoint: .plugin,
                evidence: evidence(ownership: ownership)), .notFilterKitOwned)
            XCTAssertEqual(PluginLifecyclePolicy.denial(for: .export, entryPoint: .plugin,
                evidence: evidence(ownership: ownership)), .notFilterKitOwned)
        }
    }

    func testUnverifiedPayloadOrManifestBlocksPrivilegedOperations() {
        XCTAssertEqual(PluginLifecyclePolicy.denial(for: .uninstall, entryPoint: .plugin,
            evidence: evidence(payload: .missingPlist)), .payloadNotVerified)
        XCTAssertEqual(PluginLifecyclePolicy.denial(for: .export, entryPoint: .plugin,
            evidence: evidence(manifestVerified: false)), .manifestNotVerified)
    }

    func testFixedOwnerCannotBeRemovedAndEnabledAssociationCannotBeRemoved() {
        XCTAssertEqual(PluginLifecyclePolicy.denial(for: .removeAssociation, entryPoint: .plugin,
            evidence: evidence(), associationBundleIdentifier: "com.example.owner"), .fixedOwnerImmutable)
        XCTAssertNil(PluginLifecyclePolicy.denial(for: .removeAssociation, entryPoint: .plugin,
            evidence: evidence(enabled: ["com.example.extra"]), associationBundleIdentifier: "com.example.extra"))
    }

    func testAppUninstallOnlyChangesDerivedAvailabilityNotBindingTopology() {
        let before = evidence(installed: ["com.example.owner", "com.example.extra"])
        let after = evidence(installed: ["com.example.extra"])
        XCTAssertEqual(before.allAssociatedBundleIdentifiers, after.allAssociatedBundleIdentifiers)
        XCTAssertEqual(after.unavailableAssociatedBundleIdentifiers, ["com.example.owner"])
        XCTAssertEqual(after.installedAssociatedBundleIdentifiers, ["com.example.extra"])
    }

    func testLifecycleAvailabilityProjectionMatchesBundleIdentifiersCaseInsensitively() {
        let snapshot = PluginLifecycleEvidence(ownership: .filterKit, payloadState: .verifiedPair,
            manifestVerified: true, fixedOwnerBundleIdentifier: "com.example.owner",
            additionalAssociationBundleIdentifiers: ["com.example.extra", "com.example.third"],
            enabledBundleIdentifiers: ["COM.EXAMPLE.EXTRA"],
            installedBundleIdentifiers: ["COM.EXAMPLE.OWNER", "com.example.third"])

        XCTAssertEqual(snapshot.installedAssociatedBundleIdentifiers,
            ["com.example.owner", "com.example.third"])
        XCTAssertEqual(snapshot.unavailableAssociatedBundleIdentifiers,
            ["com.example.extra"])
        XCTAssertTrue(snapshot.isEnabled(bundleIdentifier: "com.example.extra"))
        XCTAssertFalse(snapshot.isEnabled(bundleIdentifier: "COM.EXAMPLE.THIRD"))
    }

    func testLifecycleAssociationPolicyUsesCanonicalBundleIdentity() {
        XCTAssertEqual(PluginLifecyclePolicy.denial(for: .addAssociation, entryPoint: .plugin,
            evidence: evidence(), associationBundleIdentifier: "COM.EXAMPLE.OWNER"), .invalidAssociation)
        XCTAssertEqual(PluginLifecyclePolicy.denial(for: .addAssociation, entryPoint: .plugin,
            evidence: evidence(), associationBundleIdentifier: "COM.EXAMPLE.EXTRA"), .invalidAssociation)
        XCTAssertEqual(PluginLifecyclePolicy.denial(for: .removeAssociation, entryPoint: .plugin,
            evidence: evidence(), associationBundleIdentifier: "COM.EXAMPLE.OWNER"), .fixedOwnerImmutable)
        XCTAssertNil(PluginLifecyclePolicy.denial(for: .removeAssociation, entryPoint: .plugin,
            evidence: evidence(), associationBundleIdentifier: "COM.EXAMPLE.EXTRA"))
    }

    func testRemovingOneEnabledAssociationDoesNotChangeOtherAppActivationBits() throws {
        let initial = PluginBindingTopology(pluginID: UUID(),
            fixedOwnerBundleIdentifier: "com.example.owner", fixedOwnerIsEnabled: true,
            additionalAssociations: [
                PluginBindingAssociation(bundleIdentifier: "com.example.alpha", isEnabled: true),
                PluginBindingAssociation(bundleIdentifier: "com.example.beta", isEnabled: false),
                PluginBindingAssociation(bundleIdentifier: "com.example.gamma", isEnabled: true)
            ])
        let edited = try PluginBindingTopologyEditor().removeAdditionalAssociation("com.example.alpha", from: initial)

        XCTAssertEqual(edited.fixedOwnerBundleIdentifier, initial.fixedOwnerBundleIdentifier)
        XCTAssertEqual(edited.fixedOwnerIsEnabled, initial.fixedOwnerIsEnabled)
        XCTAssertEqual(edited.additionalAssociations, [
            PluginBindingAssociation(bundleIdentifier: "com.example.beta", isEnabled: false),
            PluginBindingAssociation(bundleIdentifier: "com.example.gamma", isEnabled: true)
        ])
    }

    func testReinstallRestoresAvailabilityWithoutChangingBindings() {
        let uninstalled = evidence(installed: ["com.example.extra"])
        let reinstalled = evidence(installed: ["com.example.owner", "com.example.extra"])
        XCTAssertEqual(uninstalled.allAssociatedBundleIdentifiers, reinstalled.allAssociatedBundleIdentifiers)
        XCTAssertTrue(reinstalled.unavailableAssociatedBundleIdentifiers.isEmpty)
    }
}
