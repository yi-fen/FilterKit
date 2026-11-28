import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

enum HelperRootReleaseSet {
    enum Artifact: String, CaseIterable, Hashable { case executable, deploymentManifest, launchDaemon }
    struct Verified {
        let releaseIdentifier: String
        let generation: UInt64
        let hashes: [Artifact: String]
        let byteCounts: [Artifact: Int]
    }
    static let activeReleasePointerPath = "Library/FilterKit/Helper/active-release.json"
}
struct HelperInstallerTransactionJournal { enum State { case prepared } }
struct HelperRootReleaseRecoveryAssessment {
    struct ArtifactObservation {
        let currentHash: String?
        let previousBackupHash: String?
        let currentOwnedByFilterKit: Bool
        let backupOwnedByFilterKit: Bool
    }
    struct Snapshot { let executable: ArtifactObservation; let manifest: ArtifactObservation; let launchDaemon: ArtifactObservation }
    static func assess(state: HelperInstallerTransactionJournal.State,
                       newHashes: [HelperRootReleaseSet.Artifact: String],
                       previousHashes: [HelperRootReleaseSet.Artifact: String?],
                       snapshot: Snapshot) -> Self { Self() }
}
struct HelperInstallerRecoverySnapshot {
    let stagedArtifactHashes: [HelperRootReleaseSet.Artifact: String]
    let artifactOwnershipVerified: Bool
    let previousReleasePreserved: Bool
    let previousArtifactHashes: [HelperRootReleaseSet.Artifact: String]?
    let previousArtifactOwnershipVerified: Bool
    let stagedReleaseIdentifier: String?
    let activeReleaseIdentifier: String?
    let serviceRunning: Bool
    let serviceIdentityMatchesRelease: Bool
    let provisioningEnvelopeSHA256: String?
    let previousProvisioningEnvelopeSHA256: String?
}

func expect(_ condition: @autoclosure () -> Bool, _ label: String) {
    if !condition() { fatalError("FAIL: \(label)") }
    print("PASS: \(label)")
}
func write(_ path: String, _ data: Data, mode: mode_t = 0o644) throws {
    let url = URL(fileURLWithPath: path)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard FileManager.default.createFile(atPath: path, contents: data) else { fatalError("create file failed") }
    guard chmod(path, mode) == 0 else { fatalError("chmod failed") }
}

let root = "/root/filterkit-r12-\(UUID().uuidString.lowercased())"
try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
guard chmod(root, 0o700) == 0 else { fatalError("root chmod failed") }
defer { try? FileManager.default.removeItem(atPath: root) }
let observer = HelperInstallerDescriptorFilesystemObserver(jbRootPath: root)
let activePaths: [HelperRootReleaseSet.Artifact: String] = [
    .executable: "usr/libexec/filterkit-helper",
    .deploymentManifest: "Library/FilterKit/Helper/Deployment.json",
    .launchDaemon: "Library/LaunchDaemons/cn.yfen.filterkit.helper.plist"
]
let stagedPaths: [HelperRootReleaseSet.Artifact: String] = [
    .executable: "staging/r12/usr/libexec/filterkit-helper",
    .deploymentManifest: "staging/r12/Library/FilterKit/Helper/Deployment.json",
    .launchDaemon: "staging/r12/Library/LaunchDaemons/cn.yfen.filterkit.helper.plist"
]
let payloads: [HelperRootReleaseSet.Artifact: Data] = [
    .executable: Data("helper-r11".utf8),
    .deploymentManifest: Data("{\"schemaVersion\":1}".utf8),
    .launchDaemon: Data("<?xml version=\"1.0\"?><plist/ >".utf8)
]
for artifact in HelperRootReleaseSet.Artifact.allCases {
    try write(root + "/" + activePaths[artifact]!, payloads[artifact]!)
}
let executableRecord = try observer.observeFile(relativePath: activePaths[.executable]!)
expect(executableRecord.sha256 == SHA256Digest.hex(payloads[.executable]!), "descriptor read computes expected SHA-256")
expect(executableRecord.ownerUID == 0 && executableRecord.inode > 0, "file owner and inode are captured")

do {
    _ = try observer.observeFile(relativePath: "../etc/passwd")
    fatalError("traversal unexpectedly accepted")
} catch HelperInstallerDescriptorFilesystemObserver.ObservationError.invalidRelativePath {
    expect(true, "parent traversal is rejected")
}

// Missing stage files are represented as missing, not confused with permission or integrity errors.
let missing = try observer.observeArtifactSetAllowingMissing(paths: stagedPaths)
expect(missing.values.allSatisfy { if case .missing = $0 { return true }; return false }, "absent staged artifacts are explicit missing observations")
let missingRootObserver = HelperInstallerDescriptorFilesystemObserver(jbRootPath: root + "/does-not-exist")
do {
    _ = try missingRootObserver.observeArtifactSetAllowingMissing(paths: stagedPaths)
    fatalError("missing JBROOT was incorrectly treated as missing artifacts")
} catch HelperInstallerDescriptorFilesystemObserver.ObservationError.rootUnavailable(ENOENT) {
    expect(true, "missing JBROOT is a fatal root error, not an empty artifact set")
}
let untrustedParent = root + "/untrusted-parent"
let nestedJBRoot = untrustedParent + "/jbroot"
try FileManager.default.createDirectory(atPath: nestedJBRoot, withIntermediateDirectories: true)
guard chown(untrustedParent, 501, 501) == 0, chmod(untrustedParent, 0o755) == 0 else { fatalError("untrusted parent setup failed") }
do {
    _ = try HelperInstallerDescriptorFilesystemObserver(jbRootPath: nestedJBRoot).observeFile(relativePath: activePaths[.executable]!)
    fatalError("untrusted writable parent unexpectedly accepted")
} catch HelperInstallerDescriptorFilesystemObserver.ObservationError.unsafeDirectory {
    expect(true, "non-root owner-writable JBROOT ancestor is rejected")
}

// A symlink leaf must never be followed.
let symlinkPath = root + "/Library/FilterKit/Helper/symlink-target"
try FileManager.default.createSymbolicLink(atPath: symlinkPath, withDestinationPath: activePaths[.executable]!)
do {
    _ = try observer.observeFile(relativePath: "Library/FilterKit/Helper/symlink-target")
    fatalError("symlink unexpectedly accepted")
} catch {
    expect(true, "symlink leaf is rejected")
}
let symlinkDirectory = root + "/Library/FilterKit/Helper/symlink-directory"
try FileManager.default.createSymbolicLink(atPath: symlinkDirectory, withDestinationPath: root + "/Library/FilterKit")
do {
    _ = try observer.observeFile(relativePath: "Library/FilterKit/Helper/symlink-directory/Helper/Deployment.json")
    fatalError("symlink directory unexpectedly accepted")
} catch {
    expect(true, "symlink parent directory is rejected")
}

// Hard-linked files are rejected because an external name could mutate the observed inode.
let hardlinkPath = root + "/Library/FilterKit/Helper/hardlink"
guard link((root + "/" + activePaths[.executable]!), hardlinkPath) == 0 else { fatalError("link failed") }
do {
    _ = try observer.observeFile(relativePath: "Library/FilterKit/Helper/hardlink")
    fatalError("hardlink unexpectedly accepted")
} catch HelperInstallerDescriptorFilesystemObserver.ObservationError.unsafeFile {
    expect(true, "multiple hard links are rejected")
}
_ = unlink(hardlinkPath)

// Group/world-writable artifact mode is rejected.
let writablePath = root + "/Library/FilterKit/Helper/writable"
try write(writablePath, Data("unsafe".utf8), mode: 0o666)
do {
    _ = try observer.observeFile(relativePath: "Library/FilterKit/Helper/writable")
    fatalError("writable file unexpectedly accepted")
} catch HelperInstallerDescriptorFilesystemObserver.ObservationError.unsafeFile {
    expect(true, "group/world writable file is rejected")
}

let pointer = HelperInstallerDescriptorFilesystemObserver.ReleasePointer(
    schemaVersion: 2, transactionID: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!, releaseIdentifier: "r11", generation: 11,
    artifactHashes: ["executable": SHA256Digest.hex(payloads[.executable]!),
                     "deploymentManifest": SHA256Digest.hex(payloads[.deploymentManifest]!),
                     "launchDaemon": SHA256Digest.hex(payloads[.launchDaemon]!)])
let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
try write(root + "/Library/FilterKit/Helper/active-release.json", try encoder.encode(pointer), mode: 0o600)
let readPointer = try observer.observeActiveReleasePointer()
expect(readPointer == pointer, "private active-release pointer is decoded after descriptor hash verification")

let backend = HelperInstallerArtifactReconciliationBackend(observer: observer)
let result: HelperInstallerArtifactReconciliationBackend.Result
do { result = try backend.observe(activePaths: activePaths, stagedPaths: stagedPaths, previousPaths: nil) }
catch { print("backend observation failed: \(error)"); throw error }
expect(result.activeArtifacts.values.allSatisfy { if case .present = $0 { return true }; return false }, "active release artifacts are observed")
expect(result.stagedArtifacts.values.allSatisfy { if case .missing = $0 { return true }; return false }, "staging inventory preserves missing state")
expect(result.activeReleasePointer?.releaseIdentifier == "r11", "active release pointer is exposed as an untrusted reconciliation hint")
expect(result.activePointerMatchesObservedArtifacts, "active pointer hashes must match descriptor-observed artifact bytes")
let snapshot = backend.recoverySnapshot(from: result, verifiedStagedRelease: nil,
    previousReleaseExpectedHashes: nil, serviceRunning: false,
    serviceIdentityMatchesRelease: false, provisioningEnvelopeSHA256: nil,
    previousProvisioningEnvelopeSHA256: nil)
expect(snapshot.stagedArtifactHashes.isEmpty && snapshot.activeReleaseIdentifier == "r11", "recovery snapshot distinguishes absent staged set from active pointer")
expect(snapshot.stagedReleaseIdentifier == nil, "missing stage cannot claim a verified staged release identity")

let mismatchedPointer = HelperInstallerDescriptorFilesystemObserver.ReleasePointer(
    schemaVersion: 2, transactionID: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!, releaseIdentifier: "r11", generation: 11,
    artifactHashes: ["executable": String(repeating: "f", count: 64),
                     "deploymentManifest": SHA256Digest.hex(payloads[.deploymentManifest]!),
                     "launchDaemon": SHA256Digest.hex(payloads[.launchDaemon]!)])
try write(root + "/" + HelperRootReleaseSet.activeReleasePointerPath, try encoder.encode(mismatchedPointer), mode: 0o600)
let mismatchResult = try backend.observe(activePaths: activePaths, stagedPaths: stagedPaths, previousPaths: nil)
expect(!mismatchResult.activePointerMatchesObservedArtifacts, "pointer with mismatched artifact hashes is not accepted as active identity")
let mismatchSnapshot = backend.recoverySnapshot(from: mismatchResult, verifiedStagedRelease: nil,
    previousReleaseExpectedHashes: nil, serviceRunning: false,
    serviceIdentityMatchesRelease: false, provisioningEnvelopeSHA256: nil,
    previousProvisioningEnvelopeSHA256: nil)
expect(mismatchSnapshot.activeReleaseIdentifier == nil, "mismatched pointer cannot populate trusted active release identity")

for artifact in HelperRootReleaseSet.Artifact.allCases {
    try write(root + "/" + stagedPaths[artifact]!, payloads[artifact]!)
}
let stagedObserved = try backend.observe(activePaths: activePaths, stagedPaths: stagedPaths, previousPaths: nil)
let stagedHashes = Dictionary(uniqueKeysWithValues: HelperRootReleaseSet.Artifact.allCases.map {
    ($0, SHA256Digest.hex(payloads[$0]!))
})
let verifiedStage = HelperRootReleaseSet.Verified(releaseIdentifier: "r12", generation: 12,
    hashes: stagedHashes, byteCounts: Dictionary(uniqueKeysWithValues: payloads.map { ($0.key, $0.value.count) }))
let verifiedSnapshot = backend.recoverySnapshot(from: stagedObserved, verifiedStagedRelease: verifiedStage,
    previousReleaseExpectedHashes: nil, serviceRunning: false,
    serviceIdentityMatchesRelease: false, provisioningEnvelopeSHA256: nil,
    previousProvisioningEnvelopeSHA256: nil)
expect(verifiedSnapshot.stagedReleaseIdentifier == "r12", "staged release identity derives only from verified release plus matching observed hashes")

print("R12 descriptor filesystem smoke: 18/18 assertions passed")
