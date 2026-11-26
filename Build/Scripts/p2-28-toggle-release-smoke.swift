import Foundation

enum JailbreakEnvironmentKind: String, Codable, Equatable { case rootHide, rootless, unsupported, unknown }

@main
struct P228ToggleReleaseSmoke {
    static func main() {
        let strategyEvidence = EnableDisableProfileEvidence(profileIdentifier: "roothide-ellekit-profile",
            environment: .rootHide, elleKitVersion: "observed", sourceCommit: "observed",
            sourceRevisionVerified: true, disableMechanismVerified: true,
            enableMechanismVerified: true, preservesOriginalPlistSemantics: true, deviceValidated: true)
        let strategy = EnableDisableStrategyResolver().resolve(environment: .rootHide, evidence: strategyEvidence)
        let positiveEvidence = PluginToggleReleaseEvidence(strategy: strategy,
            helperIdentityValidated: true, recoveryJournalClean: true, auditSinkWritable: true,
            pluginOwnershipVerified: true, pluginPairVerified: true, targetAppAvailable: true,
            targetIsHardBoundApp: false, userConfirmed: true)
        let decision = PluginToggleReleaseGate.evaluate(positiveEvidence)
        precondition(!PluginToggleReleaseGate.productionMutationReleased)
        precondition(decision.blockers == [.productionReleaseSwitchClosed])
        precondition(!decision.permitsMutation)

        let unverifiedStrategy = EnableDisableStrategyResolver().resolve(environment: .rootHide, evidence: nil)
        let blockedEvidence = PluginToggleReleaseEvidence(strategy: unverifiedStrategy,
            helperIdentityValidated: false, recoveryJournalClean: false, auditSinkWritable: false,
            pluginOwnershipVerified: false, pluginPairVerified: false, targetAppAvailable: false,
            targetIsHardBoundApp: true, userConfirmed: false)
        let blocked = PluginToggleReleaseGate.evaluate(blockedEvidence)
        for blocker in [PluginToggleReleaseBlocker.strategyNotDeviceVerified, .helperIdentityNotValidated,
                        .recoveryRequired, .auditUnavailable, .pluginNotFilterKitOwned,
                        .pluginPairNotVerified, .targetAppUnavailable, .hardBoundTargetImmutable,
                        .confirmationRequired, .productionReleaseSwitchClosed] {
            precondition(blocked.blockers.contains(blocker))
        }
        print("P2-28 toggle release smoke: PASS (all-positive readiness remains fail-closed; all safety blockers enforced)")
    }
}
