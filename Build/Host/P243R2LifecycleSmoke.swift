import Foundation

enum PluginOwnership: String { case filterKit, packageManager, unknown }
struct PluginAssociationPlanResolver {
    static func isValidBundleIdentifier(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count >= 2 && parts.allSatisfy { !$0.isEmpty && $0.first!.isLetter && $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" } }
    }
}
struct FilterKitManifestSoftAssociation: Equatable {
    let bundleIdentifier: String
    let isEnabled: Bool
}
enum PluginImportBindingMode { case fixedOwner, additionalAssociation }
struct PluginImportBatchDecision {
    let bindingMode: PluginImportBindingMode
    let targetBundleIdentifier: String
    let defaultsEnabled: Bool
    var fixedOwnerBundleIdentifier: String? { bindingMode == .fixedOwner ? targetBundleIdentifier : nil }
    var initialSoftAssociations: [FilterKitManifestSoftAssociation] {
        bindingMode == .additionalAssociation ? [.init(bundleIdentifier: targetBundleIdentifier, isEnabled: defaultsEnabled)] : []
    }
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError("FAIL: \(message)") }
}

let evidence = PluginLifecycleEvidence(ownership: .filterKit, payloadState: .verifiedPair,
    manifestVerified: true, fixedOwnerBundleIdentifier: "com.example.owner",
    additionalAssociationBundleIdentifiers: ["com.example.extra", "com.example.third"],
    enabledBundleIdentifiers: ["COM.EXAMPLE.EXTRA"],
    installedBundleIdentifiers: ["COM.EXAMPLE.OWNER", "com.example.third"])
expect(evidence.installedAssociatedBundleIdentifiers == ["com.example.owner", "com.example.third"], "installed projection canonical match")
expect(evidence.unavailableAssociatedBundleIdentifiers == ["com.example.extra"], "missing projection canonical match")
expect(evidence.isEnabled(bundleIdentifier: "com.example.extra"), "enabled state canonical match")
expect(!evidence.isEnabled(bundleIdentifier: "COM.EXAMPLE.THIRD"), "independent disabled state")
expect(PluginLifecyclePolicy.denial(for: .addAssociation, entryPoint: .plugin, evidence: evidence,
    associationBundleIdentifier: "COM.EXAMPLE.OWNER") == .invalidAssociation, "cannot add owner case variant")
expect(PluginLifecyclePolicy.denial(for: .addAssociation, entryPoint: .plugin, evidence: evidence,
    associationBundleIdentifier: "COM.EXAMPLE.EXTRA") == .invalidAssociation, "cannot add existing case variant")
expect(PluginLifecyclePolicy.denial(for: .removeAssociation, entryPoint: .plugin, evidence: evidence,
    associationBundleIdentifier: "COM.EXAMPLE.OWNER") == .fixedOwnerImmutable, "owner removal blocked case-insensitively")
expect(PluginLifecyclePolicy.denial(for: .removeAssociation, entryPoint: .plugin, evidence: evidence,
    associationBundleIdentifier: "COM.EXAMPLE.EXTRA") == nil, "existing association removal canonical match")

let topology = PluginBindingTopology(pluginID: UUID(), fixedOwnerBundleIdentifier: "com.example.owner",
    fixedOwnerIsEnabled: true, additionalAssociations: [
        PluginBindingAssociation(bundleIdentifier: "com.example.alpha", isEnabled: true),
        PluginBindingAssociation(bundleIdentifier: "com.example.beta", isEnabled: false),
        PluginBindingAssociation(bundleIdentifier: "com.example.gamma", isEnabled: true)
    ])
let removed = try PluginBindingTopologyEditor().removeAdditionalAssociation("COM.EXAMPLE.ALPHA", from: topology)
expect(removed.fixedOwnerBundleIdentifier == topology.fixedOwnerBundleIdentifier, "fixed owner unchanged")
expect(removed.fixedOwnerIsEnabled == topology.fixedOwnerIsEnabled, "fixed owner enabled bit unchanged")
expect(removed.additionalAssociations == [
    PluginBindingAssociation(bundleIdentifier: "com.example.beta", isEnabled: false),
    PluginBindingAssociation(bundleIdentifier: "com.example.gamma", isEnabled: true)
], "other Apps enabled bits unchanged")
let added = try PluginBindingTopologyEditor().addAdditionalAssociation("com.example.delta", to: removed)
expect(added.additionalAssociations.first(where: { $0.bundleIdentifier == "com.example.delta" })?.isEnabled == false,
       "new association defaults disabled")
print("P2-43-R2 lifecycle smoke: 12 assertions passed")
