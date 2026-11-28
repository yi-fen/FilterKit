import XCTest
@testable import FilterKit

final class HelperClientCodeIdentityRotationPolicyTests: XCTestCase {
    private final class TestProvisioningPersistence: HelperProvisioningAtomicPersistence {
        var values: [String: Data] = [:]
        func read(_ leaf: String) throws -> Data? { values[leaf] }
        func writeAtomically(_ data: Data, to leaf: String) throws { values[leaf] = data }
        func remove(_ leaf: String) throws { values.removeValue(forKey: leaf) }
    }
    private struct AcceptAllProvisioningSignatureChecker: HelperReleaseSignatureChecking {
        func verify(signature: Data, message: Data, publicKey: Data) -> Bool { true }
    }

    private func bundle(generation: UInt64, appHash: String = String(repeating: "a", count: 40),
                        bundleID: String = "cn.yfen.filterkit", team: String? = "ABCDE12345",
                        helperHash: String = String(repeating: "b", count: 40), uid: UInt32 = 501,
                        root: String = "/var/jb") -> HelperInstallerProvisioningBundle {
        HelperInstallerProvisioningBundle(schemaVersion: 2, generation: generation,
            releaseIdentifier: "r\(generation)", bundleIdentifier: bundleID,
            jbRootPath: root, appCDHash: appHash, helperCDHash: helperHash,
            allowedClientUID: uid, stagingOwnerUID: 501, routeIdentifier: "roothide",
            tweakInjectPath: "/var/jb/usr/lib/TweakInject",
            stagingRootPath: "/var/jb/var/tmp/filterkit-staging",
            socketPath: "/var/jb/Library/FilterKit/Helper/helper.sock", helperVersion: "1.0.0",
            teamIdentifier: team)
    }

    private func trustedBaseline(_ value: HelperInstallerProvisioningBundle) throws -> HelperVerifiedProvisioningBaseline {
        let envelope = HelperSignedProvisioningManifest(envelopeVersion: 1, keyIdentifier: "release-key",
            algorithm: "Ed25519", payload: value,
            signatureBase64: Data(repeating: 2, count: 64).base64EncodedString())
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(envelope)
        let verifier = HelperProvisioningSignatureVerifier(keys: [HelperReleaseSigningKey(
            identifier: "release-key", publicKeyBase64: Data(repeating: 1, count: 32).base64EncodedString(),
            status: .active, minimumGeneration: 1)], checker: AcceptAllProvisioningSignatureChecker())
        let store = HelperTrustedProvisioningStore(persistence: TestProvisioningPersistence(), verifier: verifier,
            checkpointStore: InMemoryHelperProvisioningCheckpointStore())
        return try store.commit(data, action: .install)
    }

    func testAllowsOnlyMonotonicAppCDHashRotationWithStableSignedIdentity() throws {
        XCTAssertNoThrow(try HelperClientCodeIdentityRotationPolicy.validate(
            previous: bundle(generation: 10),
            next: bundle(generation: 11, appHash: String(repeating: "c", count: 40))))
    }

    func testRejectsSameOrRegressedGeneration() {
        XCTAssertThrowsError(try HelperClientCodeIdentityRotationPolicy.validate(
            previous: bundle(generation: 10), next: bundle(generation: 10, appHash: String(repeating: "c", count: 40))))
        XCTAssertThrowsError(try HelperClientCodeIdentityRotationPolicy.validate(
            previous: bundle(generation: 10), next: bundle(generation: 9, appHash: String(repeating: "c", count: 40))))
    }

    func testRejectsBundleOrTeamIdentityChange() {
        XCTAssertThrowsError(try HelperClientCodeIdentityRotationPolicy.validate(
            previous: bundle(generation: 10),
            next: bundle(generation: 11, appHash: String(repeating: "c", count: 40), bundleID: "cn.other.app")))
        XCTAssertThrowsError(try HelperClientCodeIdentityRotationPolicy.validate(
            previous: bundle(generation: 10),
            next: bundle(generation: 11, appHash: String(repeating: "c", count: 40), team: "ZZZZZ99999")))
        XCTAssertThrowsError(try HelperClientCodeIdentityRotationPolicy.validate(
            previous: bundle(generation: 10),
            next: bundle(generation: 11, appHash: String(repeating: "c", count: 40), team: nil)))
    }

    func testRejectsHelperOrInstallContextChange() {
        XCTAssertThrowsError(try HelperClientCodeIdentityRotationPolicy.validate(
            previous: bundle(generation: 10),
            next: bundle(generation: 11, appHash: String(repeating: "c", count: 40), helperHash: String(repeating: "d", count: 40))))
        XCTAssertThrowsError(try HelperClientCodeIdentityRotationPolicy.validate(
            previous: bundle(generation: 10),
            next: bundle(generation: 11, appHash: String(repeating: "c", count: 40), uid: 502)))
    }

    func testInstallerDryRunRequiresVerifiedAndCheckpointedBaselineForRepin() throws {
        let next = bundle(generation: 11, appHash: String(repeating: "c", count: 40))
        let digests = [
            HelperInstallerArtifactDigest(relativePath: "usr/libexec/filterkit-helper", sha256: String(repeating: "1", count: 64)),
            HelperInstallerArtifactDigest(relativePath: "Library/LaunchDaemons/cn.yfen.filterkit.helper.plist", sha256: String(repeating: "2", count: 64))
        ]
        XCTAssertThrowsError(try HelperInstallerDryRun().validate(bundle: next,
            artifactDigests: digests, action: .repin)) { error in
            XCTAssertEqual(error as? HelperInstallerDryRun.DryRunError, .repinBaselineRequired)
        }
        let invalidBaseline = try trustedBaseline(bundle(generation: 10, team: "ZZZZZ99999"))
        XCTAssertThrowsError(try HelperInstallerDryRun().validate(bundle: next,
            artifactDigests: digests, action: .repin, trustedBaseline: invalidBaseline)) { error in
            XCTAssertEqual(error as? HelperInstallerDryRun.DryRunError, .invalidRepinTransition)
        }
        let validBaseline = try trustedBaseline(bundle(generation: 10))
        let report = try HelperInstallerDryRun().validate(bundle: next,
            artifactDigests: digests, action: .repin, trustedBaseline: validBaseline)
        XCTAssertFalse(report.writesPerformed)
        XCTAssertFalse(report.executionEnabled)
    }

    func testRejectsNoOpAndMalformedHashRotation() {
        XCTAssertThrowsError(try HelperClientCodeIdentityRotationPolicy.validate(
            previous: bundle(generation: 10), next: bundle(generation: 11)))
        XCTAssertThrowsError(try HelperClientCodeIdentityRotationPolicy.validate(
            previous: bundle(generation: 10), next: bundle(generation: 11, appHash: "bad")))
    }
}
