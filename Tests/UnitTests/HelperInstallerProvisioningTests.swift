import XCTest
@testable import FilterKit

final class HelperInstallerProvisioningTests: XCTestCase {
    private func sampleBundle() -> HelperInstallerProvisioningBundle {
        HelperInstallerProvisioningBundle(schemaVersion: 1, generation: 7,
            releaseIdentifier: "1.0.0-p134", bundleIdentifier: "cn.yfen.filterkit",
            jbRootPath: "/var/jb", appCDHash: String(repeating: "a", count: 40),
            helperCDHash: String(repeating: "b", count: 40), allowedClientUID: 501,
            stagingOwnerUID: 501, routeIdentifier: "dopamine-roothide",
            tweakInjectPath: "/var/jb/usr/lib/TweakInject",
            stagingRootPath: "/var/jb/var/tmp/filterkit-staging",
            socketPath: "/var/jb/Library/FilterKit/Helper/helper.sock", helperVersion: "1.0.0")
    }

    func testProvisioningProducesTwoSidedPinsAndDisabledManifest() throws {
        let bundle = sampleBundle()
        try bundle.validate()
        let app = try bundle.appTrustConfiguration()
        let manifest = try bundle.disabledRootManifest()
        XCTAssertEqual(app.allowedHelperCDHashes, [String(repeating: "b", count: 40)])
        XCTAssertEqual(manifest.allowedAppCDHashes, [String(repeating: "a", count: 40)])
        XCTAssertEqual(manifest.allowedHelperCDHashes, [String(repeating: "b", count: 40)])
        XCTAssertFalse(manifest.executionEnabled)
    }

    func testLaunchDaemonRemainsDisabled() throws {
        let data = try sampleBundle().disabledLaunchDaemonPlist()
        let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        let plist = try XCTUnwrap(object as? [String: Any])
        XCTAssertEqual(plist["Label"] as? String, "cn.yfen.filterkit.helper")
        XCTAssertEqual(plist["Disabled"] as? Bool, true)
        XCTAssertEqual(plist["RunAtLoad"] as? Bool, false)
        XCTAssertEqual(plist["KeepAlive"] as? Bool, false)
    }

    func testUpgradePlanHasRollbackAndCannotRunFromApp() throws {
        let plan = try HelperInstallerTransactionPlan.make(action: .upgrade, bundle: sampleBundle())
        XCTAssertTrue(plan.steps.contains(.preservePreviousRelease))
        XCTAssertTrue(plan.rollbackSteps.contains(.restorePreviousRelease))
        XCTAssertFalse(plan.mayRunFromApp)
        XCTAssertFalse(plan.executionEnabled)
    }

    func testInvalidUIDAndOutsideJailbreakPathsAreRejected() {
        var bundle = sampleBundle()
        bundle = HelperInstallerProvisioningBundle(schemaVersion: bundle.schemaVersion,
            generation: bundle.generation, releaseIdentifier: bundle.releaseIdentifier,
            bundleIdentifier: bundle.bundleIdentifier, jbRootPath: bundle.jbRootPath,
            appCDHash: bundle.appCDHash, helperCDHash: bundle.helperCDHash,
            allowedClientUID: 0, stagingOwnerUID: bundle.stagingOwnerUID,
            routeIdentifier: bundle.routeIdentifier, tweakInjectPath: bundle.tweakInjectPath,
            stagingRootPath: bundle.stagingRootPath, socketPath: bundle.socketPath,
            helperVersion: bundle.helperVersion)
        XCTAssertThrowsError(try bundle.validate())
    }
}
