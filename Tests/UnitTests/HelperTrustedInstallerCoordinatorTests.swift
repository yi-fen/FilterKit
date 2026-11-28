import XCTest
@testable import FilterKit

final class HelperTrustedInstallerCoordinatorTests: XCTestCase {
    private func sampleBundle() -> HelperInstallerProvisioningBundle {
        HelperInstallerProvisioningBundle(schemaVersion: 2, generation: 9,
            releaseIdentifier: "r9", bundleIdentifier: "cn.yfen.filterkit",
            jbRootPath: "/var/jb", appCDHash: String(repeating: "a", count: 40),
            helperCDHash: String(repeating: "b", count: 40), allowedClientUID: 501,
            stagingOwnerUID: 501, routeIdentifier: "roothide",
            tweakInjectPath: "/var/jb/usr/lib/TweakInject",
            stagingRootPath: "/var/jb/var/tmp/filterkit-staging",
            socketPath: "/var/jb/Library/FilterKit/Helper/helper.sock",
            helperVersion: "1.0.0", teamIdentifier: "ABCDE12345")
    }

    func testGeneratedInstallPlanRemainsDisabled() throws {
        let plan = try HelperInstallerTransactionPlan.make(action: .install, bundle: sampleBundle())
        XCTAssertFalse(plan.executionEnabled)
        XCTAssertFalse(plan.mayRunFromApp)
        XCTAssertEqual(HelperUnavailableRootInstaller().isProductionReady, false)
    }

    func testMalformedProvisioningEnvelopeIsRejectedBeforePreparation() throws {
        let bundle = sampleBundle()
        let plan = try HelperInstallerTransactionPlan.make(action: .install, bundle: bundle)
        let coordinator = HelperTrustedInstallerCoordinator(signingKeys: [],
            signatureChecker: HelperEd25519SignatureChecker())
        XCTAssertThrowsError(try coordinator.prepare(plan: plan,
            provisioningEnvelopeData: Data("{}".utf8), artifacts: [:], expectedDigests: [])) { error in
            XCTAssertEqual(error as? HelperTrustedInstallerCoordinator.Failure, .provisioningEnvelopeInvalid)
        }
    }

    func testExecutionGateBlocksGeneratedPlanEvenWithAllEvidence() throws {
        let plan = try HelperInstallerTransactionPlan.make(action: .install, bundle: sampleBundle())
        let evidence = HelperInstallerExecutionGate.Evidence(rootInstallerAvailable: true,
            releaseProvenanceVerified: true, signedArtifactsVerified: true, operatorApproved: true)
        XCTAssertEqual(HelperInstallerExecutionGate().blockReason(plan: plan, evidence: evidence), .planNotReleased)
    }
}
