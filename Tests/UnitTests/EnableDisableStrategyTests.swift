import XCTest
@testable import FilterKit

final class EnableDisableStrategyTests: XCTestCase {
    func testRootHideReferenceProfileCannotEnableMutation() {
        let result = EnableDisableStrategyResolver().resolve(environment: .rootHide, evidence: nil)
        XCTAssertEqual(result.strategy, .unverified)
        XCTAssertFalse(result.permitsMutation)
    }

    func testRootlessCannotReuseRootHideEvidence() {
        let evidence = EnableDisableProfileEvidence(profileIdentifier: "rootHide-reference",
            environment: .rootHide, elleKitVersion: "1.2-3", sourceCommit: "16e3e7e",
            sourceRevisionVerified: true, disableMechanismVerified: true,
            enableMechanismVerified: true, preservesOriginalPlistSemantics: true,
            deviceValidated: true)
        let result = EnableDisableStrategyResolver().resolve(environment: .rootless, evidence: evidence)
        XCTAssertEqual(result.status, .unsupported)
        XCTAssertFalse(result.permitsMutation)
    }

    func testSourceEvidenceWithoutDeviceValidationDoesNotEnableMutation() {
        let evidence = EnableDisableProfileEvidence(profileIdentifier: "candidate",
            environment: .rootHide, elleKitVersion: "1.2-3", sourceCommit: "16e3e7e",
            sourceRevisionVerified: true, disableMechanismVerified: true,
            enableMechanismVerified: true, preservesOriginalPlistSemantics: true,
            deviceValidated: false)
        let result = EnableDisableStrategyResolver().resolve(environment: .rootHide, evidence: evidence)
        XCTAssertEqual(result.status, .evidenceMissing)
        XCTAssertFalse(result.permitsMutation)
    }

    func testHardBoundAppCannotBeToggledEvenWithVerifiedStrategy() {
        let permission = PluginManagementPermission(access: .manageable, reasonKey: "ok")
        let denial = PluginToggleAuthorization.denial(ownership: .filterKit, permission: permission,
            isHardBoundApp: true, appIsAvailable: true, strategy: .verifiedProfileStrategy)
        XCTAssertEqual(denial, .hardBoundAssociation)
    }

    func testRuntimeSuccessRequiresObservedLoadedEvidence() {
        let snapshot = PluginDeploymentStateSnapshot(desiredState: .enabled,
            deployedState: .enabledInConfiguration, runtimeState: .notObserved, evidenceKeys: ["config.read"])
        XCTAssertFalse(snapshot.reportsInjectionSuccess)
    }
}
