import XCTest
@testable import FilterKit

final class HelperMaintenanceChannelCompatibilityTests: XCTestCase {
    private let appHash = String(repeating: "a", count: 40)
    private let helperHash = String(repeating: "b", count: 40)

    private func provisioning() -> HelperInstallerProvisioningBundle {
        HelperInstallerProvisioningBundle(schemaVersion: 2, generation: 27,
            releaseIdentifier: "p227-test", bundleIdentifier: "cn.yfen.filterkit",
            jbRootPath: "/var/jb", appCDHash: appHash, helperCDHash: helperHash,
            allowedClientUID: 501, socketGroupID: 501, stagingOwnerUID: 501,
            routeIdentifier: "roothide-ellekit", tweakInjectPath: "/var/jb/Library/TweakInject",
            stagingRootPath: "/var/jb/var/FilterKit/Staging",
            socketPath: "/var/jb/Library/FilterKit/Helper/helper.sock", helperVersion: "1.0.0")
    }

    private func appTrust() -> HelperAppTrustConfiguration {
        HelperAppTrustConfiguration(schemaVersion: 1, bundleIdentifier: "cn.yfen.filterkit",
            allowedHelperCDHashes: [helperHash], generation: 27,
            allowedHelperUIDs: [0], allowedHelperGIDs: [0])
    }

    func testMatchingProvisionedAppAndHelperIdentitiesAreAccepted() throws {
        try HelperMaintenanceChannelCompatibilityPolicy.validate(installer: provisioning(), appTrust: appTrust(),
            observedAppCDHash: appHash, observedHelperCDHash: helperHash,
            observedClientUID: 501, observedClientGID: 501, observedHelperUID: 0, observedHelperGID: 0)
    }

    func testAppCDHashMismatchIsRejected() {
        XCTAssertThrowsError(try HelperMaintenanceChannelCompatibilityPolicy.validate(installer: provisioning(), appTrust: appTrust(),
            observedAppCDHash: String(repeating: "c", count: 40), observedHelperCDHash: helperHash,
            observedClientUID: 501, observedClientGID: 501, observedHelperUID: 0, observedHelperGID: 0)) { error in
            XCTAssertEqual(error as? HelperMaintenanceChannelCompatibilityPolicy.Failure, .appCDHashMismatch)
        }
    }

    func testHelperCDHashMismatchIsRejected() {
        XCTAssertThrowsError(try HelperMaintenanceChannelCompatibilityPolicy.validate(installer: provisioning(), appTrust: appTrust(),
            observedAppCDHash: appHash, observedHelperCDHash: String(repeating: "d", count: 40),
            observedClientUID: 501, observedClientGID: 501, observedHelperUID: 0, observedHelperGID: 0)) { error in
            XCTAssertEqual(error as? HelperMaintenanceChannelCompatibilityPolicy.Failure, .helperCDHashMismatch)
        }
    }

    func testUIDAndGIDMismatchesAreRejected() {
        XCTAssertThrowsError(try HelperMaintenanceChannelCompatibilityPolicy.validate(installer: provisioning(), appTrust: appTrust(),
            observedAppCDHash: appHash, observedHelperCDHash: helperHash,
            observedClientUID: 502, observedClientGID: 501, observedHelperUID: 0, observedHelperGID: 0))
        XCTAssertThrowsError(try HelperMaintenanceChannelCompatibilityPolicy.validate(installer: provisioning(), appTrust: appTrust(),
            observedAppCDHash: appHash, observedHelperCDHash: helperHash,
            observedClientUID: 501, observedClientGID: 502, observedHelperUID: 0, observedHelperGID: 0))
    }

    func testNonRootHelperIdentityIsRejected() {
        XCTAssertThrowsError(try HelperMaintenanceChannelCompatibilityPolicy.validate(installer: provisioning(), appTrust: appTrust(),
            observedAppCDHash: appHash, observedHelperCDHash: helperHash,
            observedClientUID: 501, observedClientGID: 501, observedHelperUID: 501, observedHelperGID: 0))
    }

    func testAppTrustGenerationAndHelperPinMustMatchInstaller() {
        let stale = HelperAppTrustConfiguration(schemaVersion: 1, bundleIdentifier: "cn.yfen.filterkit",
            allowedHelperCDHashes: [helperHash], generation: 26, allowedHelperUIDs: [0], allowedHelperGIDs: [0])
        XCTAssertThrowsError(try HelperMaintenanceChannelCompatibilityPolicy.validate(installer: provisioning(), appTrust: stale,
            observedAppCDHash: appHash, observedHelperCDHash: helperHash,
            observedClientUID: 501, observedClientGID: 501, observedHelperUID: 0, observedHelperGID: 0))
    }
}
