import XCTest
@testable import FilterKit

final class HelperReleaseTrustTests: XCTestCase {
    private func fixture(policy: HelperReleaseTrustManifest.PublisherPolicy = .integrityOnly,
                        team: String? = nil, certificate: String? = nil) -> HelperReleaseTrustManifest {
        HelperReleaseTrustManifest(schemaVersion: 1, releaseIdentifier: "release-p141", generation: 41,
            bundleIdentifier: "cn.yfen.filterkit.helper", helperVersion: "1.4.1",
            helperCDHash: String(repeating: "a", count: 40),
            helperSHA256: String(repeating: "b", count: 64), publisherPolicy: policy,
            teamIdentifier: team, leafCertificateSHA256: certificate)
    }

    func testIntegrityOnlyManifestValidatesAndRejectsMalformedDigest() throws {
        try fixture().validate()
        let malformed = HelperReleaseTrustManifest(schemaVersion: 1, releaseIdentifier: "release-p141",
            generation: 41, bundleIdentifier: "cn.yfen.filterkit.helper", helperVersion: "1.4.1",
            helperCDHash: String(repeating: "a", count: 40), helperSHA256: "bad",
            publisherPolicy: .integrityOnly, teamIdentifier: nil, leafCertificateSHA256: nil)
        XCTAssertThrowsError(try malformed.validate())
    }

    func testPinnedPublisherRequiresTeamAndCertificate() {
        XCTAssertThrowsError(try fixture(policy: .pinnedAppleIdentity).validate())
        XCTAssertNoThrow(try fixture(policy: .pinnedAppleIdentity, team: "ABCDE12345",
                                      certificate: String(repeating: "c", count: 64)).validate())
    }

    func testReleaseVerifierRejectsDigestAndCDHashMismatch() throws {
        let manifest = fixture()
        let provisioning = HelperInstallerProvisioningBundle(schemaVersion: 2, generation: 41,
            releaseIdentifier: "release-p141", bundleIdentifier: "cn.yfen.filterkit.helper",
            jbRootPath: "/var/jb", appCDHash: String(repeating: "d", count: 40),
            helperCDHash: String(repeating: "a", count: 40), allowedClientUID: 501,
            stagingOwnerUID: 501, routeIdentifier: "rootless", tweakInjectPath: "/var/jb/Library/TweakInject",
            stagingRootPath: "/var/jb/var/tmp/FilterKit", socketPath: "/var/jb/Library/FilterKit/Helper/helper.sock",
            helperVersion: "1.4.1")
        let verifier = HelperReleaseTrustVerifier()
        XCTAssertNoThrow(try verifier.verify(manifest: manifest, provisioning: provisioning,
            observedHelperSHA256: manifest.helperSHA256, runningCDHash: manifest.helperCDHash))
        XCTAssertThrowsError(try verifier.verify(manifest: manifest, provisioning: provisioning,
            observedHelperSHA256: String(repeating: "e", count: 64), runningCDHash: manifest.helperCDHash))
        XCTAssertThrowsError(try verifier.verify(manifest: manifest, provisioning: provisioning,
            observedHelperSHA256: manifest.helperSHA256, runningCDHash: String(repeating: "f", count: 40)))
    }
}
