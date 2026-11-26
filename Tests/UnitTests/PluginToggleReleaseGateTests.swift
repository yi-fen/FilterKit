import XCTest
@testable import FilterKit

final class PluginToggleReleaseGateTests: XCTestCase {
    private func verifiedStrategy(deviceValidated: Bool = true) -> EnableDisableStrategyResolution {
        let evidence = EnableDisableProfileEvidence(profileIdentifier: "roothide-ellekit-profile",
            environment: .rootHide, elleKitVersion: "device-observed", sourceCommit: "device-verified",
            sourceRevisionVerified: true, disableMechanismVerified: true,
            enableMechanismVerified: true, preservesOriginalPlistSemantics: true,
            deviceValidated: deviceValidated)
        return EnableDisableStrategyResolver().resolve(environment: .rootHide, evidence: evidence)
    }

    private func evidence(strategy: EnableDisableStrategyResolution? = nil,
                          helperIdentityValidated: Bool = true,
                          recoveryJournalClean: Bool = true,
                          auditSinkWritable: Bool = true,
                          pluginOwnershipVerified: Bool = true,
                          pluginPairVerified: Bool = true,
                          targetAppAvailable: Bool = true,
                          targetIsHardBoundApp: Bool = false,
                          userConfirmed: Bool = true) -> PluginToggleReleaseEvidence {
        PluginToggleReleaseEvidence(strategy: strategy ?? verifiedStrategy(),
            helperIdentityValidated: helperIdentityValidated,
            recoveryJournalClean: recoveryJournalClean,
            auditSinkWritable: auditSinkWritable,
            pluginOwnershipVerified: pluginOwnershipVerified,
            pluginPairVerified: pluginPairVerified,
            targetAppAvailable: targetAppAvailable,
            targetIsHardBoundApp: targetIsHardBoundApp,
            userConfirmed: userConfirmed)
    }

    func testProductionMutationRemainsClosedEvenWhenAllEvidenceIsPositive() {
        let decision = PluginToggleReleaseGate.evaluate(evidence())
        XCTAssertFalse(PluginToggleReleaseGate.productionMutationReleased)
        XCTAssertTrue(decision.blockers.contains(.productionReleaseSwitchClosed))
        XCTAssertFalse(decision.permitsMutation)
    }

    func testMissingDeviceValidatedStrategyBlocksEnableAndDisable() {
        let decision = PluginToggleReleaseGate.evaluate(evidence(strategy: verifiedStrategy(deviceValidated: false)))
        XCTAssertTrue(decision.blockers.contains(.strategyNotDeviceVerified))
        XCTAssertFalse(decision.permitsMutation)
    }

    func testHelperIdentityRecoveryAndAuditAreIndependentBarriers() {
        let decision = PluginToggleReleaseGate.evaluate(evidence(helperIdentityValidated: false,
            recoveryJournalClean: false, auditSinkWritable: false))
        XCTAssertTrue(decision.blockers.contains(.helperIdentityNotValidated))
        XCTAssertTrue(decision.blockers.contains(.recoveryRequired))
        XCTAssertTrue(decision.blockers.contains(.auditUnavailable))
    }

    func testOwnershipPairAvailabilityAndHardBoundRulesBlockMutation() {
        let decision = PluginToggleReleaseGate.evaluate(evidence(pluginOwnershipVerified: false,
            pluginPairVerified: false, targetAppAvailable: false, targetIsHardBoundApp: true))
        XCTAssertTrue(decision.blockers.contains(.pluginNotFilterKitOwned))
        XCTAssertTrue(decision.blockers.contains(.pluginPairNotVerified))
        XCTAssertTrue(decision.blockers.contains(.targetAppUnavailable))
        XCTAssertTrue(decision.blockers.contains(.hardBoundTargetImmutable))
    }

    func testExplicitConfirmationIsRequired() {
        let decision = PluginToggleReleaseGate.evaluate(evidence(userConfirmed: false))
        XCTAssertTrue(decision.blockers.contains(.confirmationRequired))
    }
}
