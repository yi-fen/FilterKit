import XCTest
@testable import FilterKit

final class HelperTrustedProvisioningStoreTests: XCTestCase {
    private struct AcceptAll: HelperReleaseSignatureChecking {
        func verify(signature: Data, message: Data, publicKey: Data) -> Bool { true }
    }
    private final class MemoryPersistence: HelperProvisioningAtomicPersistence {
        var values: [String: Data] = [:]
        func read(_ leaf: String) throws -> Data? { values[leaf] }
        func writeAtomically(_ data: Data, to leaf: String) throws { values[leaf] = data }
        func remove(_ leaf: String) throws { values.removeValue(forKey: leaf) }
    }
    private final class FailOnceCheckpointStore: HelperProvisioningCheckpointStoring {
        let backing = InMemoryHelperProvisioningCheckpointStore()
        var shouldFail = true
        func highestCheckpoint(for bundleIdentifier: String) throws -> HelperProvisioningCheckpoint? {
            try backing.highestCheckpoint(for: bundleIdentifier)
        }
        func record(_ checkpoint: HelperProvisioningCheckpoint, for bundleIdentifier: String) throws {
            if shouldFail { shouldFail = false; throw TestFailure.injected }
            try backing.record(checkpoint, for: bundleIdentifier)
        }
        enum TestFailure: Error { case injected }
    }

    private let key = HelperReleaseSigningKey(identifier: "release-key",
        publicKeyBase64: Data(repeating: 1, count: 32).base64EncodedString(), status: .active, minimumGeneration: 1)

    private func bundle(_ generation: UInt64, appHash: String = String(repeating: "a", count: 40),
                        helperHash: String = String(repeating: "b", count: 40)) -> HelperInstallerProvisioningBundle {
        HelperInstallerProvisioningBundle(schemaVersion: 2, generation: generation,
            releaseIdentifier: "r\(generation)", bundleIdentifier: "cn.yfen.filterkit",
            jbRootPath: "/var/jb", appCDHash: appHash, helperCDHash: helperHash,
            allowedClientUID: 501, stagingOwnerUID: 501, routeIdentifier: "roothide",
            tweakInjectPath: "/var/jb/usr/lib/TweakInject",
            stagingRootPath: "/var/jb/var/tmp/filterkit-staging",
            socketPath: "/var/jb/Library/FilterKit/Helper/helper.sock", helperVersion: "1.0.0",
            teamIdentifier: "ABCDE12345")
    }

    private func encoded(_ bundle: HelperInstallerProvisioningBundle) throws -> Data {
        let envelope = HelperSignedProvisioningManifest(envelopeVersion: 1, keyIdentifier: "release-key",
            algorithm: "Ed25519", payload: bundle,
            signatureBase64: Data(repeating: 2, count: 64).base64EncodedString())
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(envelope)
    }

    private func store(_ persistence: MemoryPersistence,
                       checkpoints: HelperProvisioningCheckpointStoring) -> HelperTrustedProvisioningStore {
        HelperTrustedProvisioningStore(persistence: persistence,
            verifier: HelperProvisioningSignatureVerifier(keys: [key], checker: AcceptAll()),
            checkpointStore: checkpoints)
    }

    func testCommitAndLoadEstablishVerifiedBaselineAndCheckpoint() throws {
        let persistence = MemoryPersistence()
        let checkpoints = InMemoryHelperProvisioningCheckpointStore()
        let trusted = store(persistence, checkpoints: checkpoints)
        let data = try encoded(bundle(10))
        let baseline = try trusted.commit(data, action: .install)
        XCTAssertEqual(baseline.payload.generation, 10)
        XCTAssertEqual(try trusted.loadTrustedBaseline().envelopeSHA256, baseline.envelopeSHA256)
        XCTAssertEqual(try checkpoints.highestCheckpoint(for: "cn.yfen.filterkit")?.generation, 10)
    }

    func testRepinRequiresVerifiedBaselineAndMonotonicIdentityRotation() throws {
        let persistence = MemoryPersistence()
        let checkpoints = InMemoryHelperProvisioningCheckpointStore()
        let trusted = store(persistence, checkpoints: checkpoints)
        _ = try trusted.commit(encoded(bundle(10)), action: .install)
        let next = try encoded(bundle(11, appHash: String(repeating: "c", count: 40)))
        XCTAssertEqual(try trusted.commit(next, action: .repin).payload.generation, 11)
        XCTAssertEqual(try trusted.loadTrustedBaseline().payload.appCDHash, String(repeating: "c", count: 40))
    }

    func testInterruptedCheckpointIsRecoveredFromPendingIntent() throws {
        let persistence = MemoryPersistence()
        let checkpoints = FailOnceCheckpointStore()
        let trusted = store(persistence, checkpoints: checkpoints)
        let data = try encoded(bundle(20))
        XCTAssertThrowsError(try trusted.commit(data, action: .install))
        XCTAssertNotNil(persistence.values["provisioning.pending.json"])
        try trusted.recoverPendingTransaction()
        XCTAssertNil(persistence.values["provisioning.pending.json"])
        XCTAssertEqual(try trusted.loadTrustedBaseline().payload.generation, 20)
    }

    func testUpgradeMayRotateHelperButMustPreserveAppAndInstallContext() throws {
        let persistence = MemoryPersistence()
        let trusted = store(persistence, checkpoints: InMemoryHelperProvisioningCheckpointStore())
        _ = try trusted.commit(encoded(bundle(50)), action: .install)
        let appIdentityChange = try encoded(bundle(51, appHash: String(repeating: "c", count: 40),
            helperHash: String(repeating: "d", count: 40)))
        XCTAssertThrowsError(try trusted.commit(appIdentityChange, action: .upgrade))
        let helperUpgrade = try encoded(bundle(51, helperHash: String(repeating: "d", count: 40)))
        XCTAssertEqual(try trusted.commit(helperUpgrade, action: .upgrade).payload.helperCDHash,
            String(repeating: "d", count: 40))
    }

    func testCheckpointNormalizesBundleIdentifierCase() throws {
        let checkpoints = InMemoryHelperProvisioningCheckpointStore()
        let checkpoint = HelperProvisioningCheckpoint(generation: 42, envelopeSHA256: String(repeating: "a", count: 64))
        try checkpoints.record(checkpoint, for: "cn.yfen.filterkit")
        XCTAssertEqual(try checkpoints.highestCheckpoint(for: "CN.YFEN.FILTERKIT"), checkpoint)
    }

    func testTamperedCurrentFileCannotReplaceCheckpointAtSameGeneration() throws {
        let persistence = MemoryPersistence()
        let checkpoints = InMemoryHelperProvisioningCheckpointStore()
        let trusted = store(persistence, checkpoints: checkpoints)
        let original = try encoded(bundle(30))
        _ = try trusted.commit(original, action: .install)
        persistence.values["provisioning.signed.json"] = try encoded(bundle(30, appHash: String(repeating: "c", count: 40)))
        XCTAssertThrowsError(try trusted.loadTrustedBaseline()) { error in
            XCTAssertEqual(error as? HelperTrustedProvisioningStore.Failure, .rollbackDetected)
        }
    }
}
