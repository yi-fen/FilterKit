import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

struct AcceptAllChecker: HelperReleaseSignatureChecking {
    func verify(signature: Data, message: Data, publicKey: Data) -> Bool { true }
}
final class MemoryProvisioningPersistence: HelperProvisioningAtomicPersistence {
    var values: [String: Data] = [:]
    func read(_ leaf: String) throws -> Data? { values[leaf] }
    func writeAtomically(_ data: Data, to leaf: String) throws { values[leaf] = data }
    func remove(_ leaf: String) throws { values.removeValue(forKey: leaf) }
}
final class FailOnceCheckpoint: HelperProvisioningCheckpointStoring {
    let backing = InMemoryHelperProvisioningCheckpointStore()
    var fail = true
    func highestCheckpoint(for bundleIdentifier: String) throws -> HelperProvisioningCheckpoint? {
        try backing.highestCheckpoint(for: bundleIdentifier)
    }
    func record(_ checkpoint: HelperProvisioningCheckpoint, for bundleIdentifier: String) throws {
        if fail { fail = false; throw NSError(domain: "smoke", code: 1) }
        try backing.record(checkpoint, for: bundleIdentifier)
    }
}

func expect(_ condition: @autoclosure () -> Bool, _ label: String) {
    if !condition() { fputs("FAIL: \(label)\n", stderr); exit(1) }
    print("PASS: \(label)")
}
let key = HelperReleaseSigningKey(identifier: "release-key",
    publicKeyBase64: Data(repeating: 1, count: 32).base64EncodedString(), status: .active,
    minimumGeneration: 1, maximumGeneration: nil)
let verifier = HelperProvisioningSignatureVerifier(keys: [key], checker: AcceptAllChecker())
func makeBundle(_ generation: UInt64, appHash: String = String(repeating: "a", count: 40),
                helperHash: String = String(repeating: "b", count: 40)) -> HelperInstallerProvisioningBundle {
    HelperInstallerProvisioningBundle(schemaVersion: 2, generation: generation,
        releaseIdentifier: "r\(generation)", bundleIdentifier: "cn.yfen.filterkit",
        jbRootPath: "/var/jb", appCDHash: appHash, helperCDHash: helperHash,
        allowedClientUID: 501, stagingOwnerUID: 501, routeIdentifier: "roothide",
        tweakInjectPath: "/var/jb/usr/lib/TweakInject", stagingRootPath: "/var/jb/var/tmp/filterkit-staging",
        socketPath: "/var/jb/Library/FilterKit/Helper/helper.sock", helperVersion: "1.0.0",
        teamIdentifier: "ABCDE12345")
}
func encode(_ bundle: HelperInstallerProvisioningBundle) throws -> Data {
    let envelope = HelperSignedProvisioningManifest(envelopeVersion: 1, keyIdentifier: "release-key",
        algorithm: "Ed25519", payload: bundle,
        signatureBase64: Data(repeating: 2, count: 64).base64EncodedString())
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(envelope)
}

let persistence = MemoryProvisioningPersistence()
let checkpoints = InMemoryHelperProvisioningCheckpointStore()
let trusted = HelperTrustedProvisioningStore(persistence: persistence, verifier: verifier, checkpointStore: checkpoints)
let first = try encode(makeBundle(10))
let baseline = try trusted.commit(first, action: .install)
expect(baseline.payload.generation == 10, "install writes signed provisioning and returns verified baseline")
let loadedFirst = try trusted.loadTrustedBaseline()
expect(loadedFirst.payload.generation == 10, "load verifies persisted baseline and checkpoint")
let next = try encode(makeBundle(11, appHash: String(repeating: "c", count: 40)))
let rotated = try trusted.commit(next, action: .repin)
expect(rotated.payload.generation == 11, "repin accepts only monotonic signed identity rotation")

let tampered = try encode(makeBundle(11, appHash: String(repeating: "d", count: 40)))
persistence.values["provisioning.signed.json"] = tampered
var rejectedSameGeneration = false
do { _ = try trusted.loadTrustedBaseline() } catch { rejectedSameGeneration = true }
expect(rejectedSameGeneration, "same-generation alternate envelope rejected by digest checkpoint")

let crashPersistence = MemoryProvisioningPersistence()
let crashCheckpoint = FailOnceCheckpoint()
let crashStore = HelperTrustedProvisioningStore(persistence: crashPersistence, verifier: verifier, checkpointStore: crashCheckpoint)
let crashCandidate = try encode(makeBundle(20))
var injectedFailure = false
do { _ = try crashStore.commit(crashCandidate, action: .install) } catch { injectedFailure = true }
expect(injectedFailure && crashPersistence.values["provisioning.pending.json"] != nil,
       "interrupted commit leaves durable pending intent")
try crashStore.recoverPendingTransaction()
expect(crashPersistence.values["provisioning.pending.json"] == nil,
       "recovery reconciles current signed envelope and clears pending intent")
let recovered = try crashStore.loadTrustedBaseline()
expect(recovered.payload.generation == 20, "recovered provisioning generation becomes trusted checkpoint")

let rootOwnedDirectory = NSTemporaryDirectory() + "filterkit-r8-" + UUID().uuidString
try FileManager.default.createDirectory(atPath: rootOwnedDirectory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(atPath: rootOwnedDirectory) }
expect(chmod(rootOwnedDirectory, 0o700) == 0, "host creates pre-provisioned 0700 test directory")
let posixStore = HelperRootOwnedProvisioningFileStore(directoryPath: rootOwnedDirectory)
try posixStore.writeAtomically(first, to: "provisioning.signed.json")
let posixFirst = try posixStore.read("provisioning.signed.json")
expect(posixFirst == first, "root-owned POSIX store atomically writes and reads signed file")
try posixStore.writeAtomically(next, to: "provisioning.signed.json")
let posixNext = try posixStore.read("provisioning.signed.json")
expect(posixNext == next, "root-owned POSIX store atomically replaces current file")

let canonicalCheckpoints = InMemoryHelperProvisioningCheckpointStore()
let caseCheckpoint = HelperProvisioningCheckpoint(generation: 42, envelopeSHA256: String(repeating: "e", count: 64))
try canonicalCheckpoints.record(caseCheckpoint, for: "cn.yfen.filterkit")
let caseLookup = try canonicalCheckpoints.highestCheckpoint(for: "CN.YFEN.FILTERKIT")
expect(caseLookup == caseCheckpoint, "checkpoint key canonicalizes Bundle ID case")

let upgradePersistence = MemoryProvisioningPersistence()
let upgradeStore = HelperTrustedProvisioningStore(persistence: upgradePersistence, verifier: verifier,
    checkpointStore: InMemoryHelperProvisioningCheckpointStore())
_ = try upgradeStore.commit(encode(makeBundle(60)), action: .install)
var appIdentityUpgradeRejected = false
do {
    _ = try upgradeStore.commit(encode(makeBundle(61, appHash: String(repeating: "d", count: 40),
        helperHash: String(repeating: "e", count: 40))), action: .upgrade)
} catch { appIdentityUpgradeRejected = true }
expect(appIdentityUpgradeRejected, "Helper upgrade cannot silently rotate App CDHash")
let helperUpgrade = try upgradeStore.commit(encode(makeBundle(61, helperHash: String(repeating: "e", count: 40))), action: .upgrade)
expect(helperUpgrade.payload.helperCDHash == String(repeating: "e", count: 40),
       "Helper upgrade can rotate Helper CDHash while preserving App identity")
