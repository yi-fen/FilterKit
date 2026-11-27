import Foundation

/// P2-28 first rollout gate for per-App plugin enable/disable and injection.
/// Readiness evidence is deliberately separate from the hard production release switch.
struct PluginToggleReleaseEvidence: Equatable {
    let strategy: EnableDisableStrategyResolution
    let helperIdentityValidated: Bool
    let recoveryJournalClean: Bool
    let auditSinkWritable: Bool
    let pluginOwnershipVerified: Bool
    let pluginPairVerified: Bool
    let targetAppAvailable: Bool
    /// Retained as context for audit/reporting. Hard binding does not prohibit activation toggles.
    let targetIsHardBoundApp: Bool
    let userConfirmed: Bool
}

enum PluginToggleReleaseBlocker: String, Codable, Equatable, CaseIterable {
    case strategyNotDeviceVerified
    case helperIdentityNotValidated
    case recoveryRequired
    case auditUnavailable
    case pluginNotFilterKitOwned
    case pluginPairNotVerified
    case targetAppUnavailable
    /// Deprecated compatibility case. Hard binding is no longer a toggle blocker.
    case hardBoundTargetImmutable
    case confirmationRequired
    case productionReleaseSwitchClosed
}

struct PluginToggleReleaseDecision: Equatable {
    let blockers: [PluginToggleReleaseBlocker]
    var isReadyForRelease: Bool { blockers.isEmpty }
    var permitsMutation: Bool { isReadyForRelease }
}

/// This switch is intentionally false in P2-28. A readiness decision alone must never
/// activate filesystem writes or injection on an unvalidated RootHide device.
enum PluginToggleReleaseGate {
    static let productionMutationReleased = false

    static func evaluate(_ evidence: PluginToggleReleaseEvidence) -> PluginToggleReleaseDecision {
        var blockers: [PluginToggleReleaseBlocker] = []
        if !evidence.strategy.permitsMutation { blockers.append(.strategyNotDeviceVerified) }
        if !evidence.helperIdentityValidated { blockers.append(.helperIdentityNotValidated) }
        if !evidence.recoveryJournalClean { blockers.append(.recoveryRequired) }
        if !evidence.auditSinkWritable { blockers.append(.auditUnavailable) }
        if !evidence.pluginOwnershipVerified { blockers.append(.pluginNotFilterKitOwned) }
        if !evidence.pluginPairVerified { blockers.append(.pluginPairNotVerified) }
        if !evidence.targetAppAvailable { blockers.append(.targetAppUnavailable) }
        if !evidence.userConfirmed { blockers.append(.confirmationRequired) }
        if !productionMutationReleased { blockers.append(.productionReleaseSwitchClosed) }
        return PluginToggleReleaseDecision(blockers: blockers)
    }
}
