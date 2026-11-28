import XCTest
@testable import FilterKit

final class HelperTrustProvisioningTests: XCTestCase {
    private let appHash = String(repeating: "a", count: 40)
    private let helperHash = String(repeating: "b", count: 40)

    func testPinSetAcceptsExactInstallerPins() throws {
        let pins = HelperTrustPinSet(schemaVersion: 1, bundleIdentifier: "cn.yfen.filterkit",
            allowedClientUIDs: [501], allowedAppCDHashes: [appHash],
            allowedHelperCDHashes: [helperHash], generation: 1)
        XCTAssertNoThrow(try pins.validate())
    }

    func testPinSetRejectsMissingOrMalformedPins() {
        let missing = HelperTrustPinSet(schemaVersion: 1, bundleIdentifier: "cn.yfen.filterkit",
            allowedClientUIDs: [501], allowedAppCDHashes: [],
            allowedHelperCDHashes: [helperHash], generation: 1)
        XCTAssertThrowsError(try missing.validate())

        let malformed = HelperTrustPinSet(schemaVersion: 1, bundleIdentifier: "cn.yfen.filterkit",
            allowedClientUIDs: [501], allowedAppCDHashes: ["not-a-cdhash"],
            allowedHelperCDHashes: [helperHash], generation: 1)
        XCTAssertThrowsError(try malformed.validate())
    }

    func testPinSetRejectsRootClientAndDuplicatePins() {
        let rootClient = HelperTrustPinSet(schemaVersion: 1, bundleIdentifier: "cn.yfen.filterkit",
            allowedClientUIDs: [0], allowedAppCDHashes: [appHash],
            allowedHelperCDHashes: [helperHash], generation: 1)
        XCTAssertThrowsError(try rootClient.validate())

        let duplicate = HelperTrustPinSet(schemaVersion: 1, bundleIdentifier: "cn.yfen.filterkit",
            allowedClientUIDs: [501], allowedAppCDHashes: [appHash, appHash.uppercased()],
            allowedHelperCDHashes: [helperHash], generation: 1)
        XCTAssertThrowsError(try duplicate.validate())
    }

    func testHelperManifestTrustValidationRequiresBothRoles() {
        let manifest = HelperDeploymentManifest.disabledTemplate(routeIdentifier: "roothide",
            jbRootPath: "/var/jb", tweakInjectPath: "/var/jb/usr/lib/TweakInject",
            stagingRootPath: "/var/jb/var/mobile/FilterKit/Staging",
            socketPath: "/var/jb/var/run/filterkit.sock", appCDHashes: [],
            helperCDHashes: [helperHash], allowedClientUIDs: [501], stagingOwnerUID: 501)
        XCTAssertThrowsError(try HelperTrustConfigurationValidator.validate(manifest))
    }
    func testProvisioningCarriesTrustedBundleAndTeamIdentityIntoRootManifest() throws {
        let pins = HelperTrustPinSet(schemaVersion: 1, bundleIdentifier: "cn.yfen.filterkit",
            allowedClientUIDs: [501], allowedAppCDHashes: [appHash],
            allowedHelperCDHashes: [helperHash], generation: 2,
            clientTeamIdentifier: "ABCDE12345")
        let manifest = try pins.makeDisabledManifest(routeIdentifier: "roothide",
            jbRootPath: "/var/jb", tweakInjectPath: "/var/jb/usr/lib/TweakInject",
            stagingRootPath: "/var/jb/var/mobile/FilterKit/Staging",
            socketPath: "/var/jb/Library/FilterKit/Helper/helper.sock", stagingOwnerUID: 501)
        XCTAssertEqual(manifest.allowedClientBundleIdentifier, "cn.yfen.filterkit")
        XCTAssertEqual(manifest.allowedClientTeamIdentifier, "ABCDE12345")
        XCTAssertNoThrow(try HelperTrustConfigurationValidator.validate(manifest))
    }

    func testRuntimeTrustRejectsMissingTeamIdentityBinding() {
        let manifest = HelperDeploymentManifest.disabledTemplate(routeIdentifier: "roothide",
            jbRootPath: "/var/jb", tweakInjectPath: "/var/jb/usr/lib/TweakInject",
            stagingRootPath: "/var/jb/var/mobile/FilterKit/Staging",
            socketPath: "/var/jb/Library/FilterKit/Helper/helper.sock",
            appCDHashes: [appHash], helperCDHashes: [helperHash], allowedClientUIDs: [501],
            stagingOwnerUID: 501, allowedClientBundleIdentifier: "cn.yfen.filterkit")
        XCTAssertThrowsError(try HelperTrustConfigurationValidator.validate(manifest))
    }

}
