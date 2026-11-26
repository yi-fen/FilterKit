import Foundation

/// UI eligibility for the P2-03 read-only association preview. This policy never authorizes writes.
enum PluginAssociationPreviewBlocker: String, Codable, Equatable {
    case thirdPartyPlugin
    case pluginNotManageable
    case pluginNotPaired
    case hardBoundAppIsImmutable
    case targetAppUnavailable
    case originalPlistUnavailable
}

struct PluginAssociationPreviewEligibility: Equatable {
    let isEligible: Bool
    let blockers: [PluginAssociationPreviewBlocker]
}

struct PluginAssociationPreviewPolicy {
    func evaluate(plugin: PluginScanItem, targetBundleIdentifier: String,
                  installedBundleIdentifiers: Set<String>, originalPlistIsReadable: Bool) -> PluginAssociationPreviewEligibility {
        var blockers: [PluginAssociationPreviewBlocker] = []
        if plugin.ownership != .filterKit { blockers.append(.thirdPartyPlugin) }
        if plugin.managementPermission?.canModify != true { blockers.append(.pluginNotManageable) }
        if plugin.pairingState != .paired { blockers.append(.pluginNotPaired) }
        if let hardBound = plugin.hardBoundBundleIdentifier, hardBound == targetBundleIdentifier {
            blockers.append(.hardBoundAppIsImmutable)
        }
        if !PluginAssociationPlanResolver.isValidBundleIdentifier(targetBundleIdentifier) ||
            !installedBundleIdentifiers.contains(targetBundleIdentifier) {
            blockers.append(.targetAppUnavailable)
        }
        if !originalPlistIsReadable { blockers.append(.originalPlistUnavailable) }
        return PluginAssociationPreviewEligibility(isEligible: blockers.isEmpty, blockers: blockers)
    }
}
