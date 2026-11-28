import Foundation

enum HelperRootReleaseSet {
    enum Artifact: String, CaseIterable, Hashable { case executable, deploymentManifest, launchDaemon }
    static let executablePath = "usr/libexec/filterkit-helper"
    static let manifestPath = "Library/FilterKit/Helper/Deployment.json"
    static let launchDaemonPath = "Library/LaunchDaemons/cn.yfen.filterkit.helper.plist"
    struct Verified { let releaseIdentifier: String; let generation: UInt64; let hashes: [Artifact: String]; let byteCounts: [Artifact: Int] }
}
enum HelperPolicy {
    static func isValidHash(_ value: String) -> Bool { value.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil }
    static func isSafeRelativePath(_ value: String) -> Bool {
        !value.isEmpty && !value.hasPrefix("/") && !value.contains("\\") && !value.contains("\0")
            && value.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }
}
struct HelperInstallerTransactionJournal {
    enum Action: Equatable { case install, upgrade, repin }
    enum State: Equatable { case rollbackRequired }
    let action: Action; let state: State; let pendingOperation: String?; let sequence: UInt64; let previousEventHash: String
    func validateChain() throws {}
}
enum HelperInstallerSharedTransactionLock {
    static func withExclusiveLock<T>(jbroot: String, body: () throws -> T) throws -> T { try body() }
}
struct HelperInstallerDurableJournalStore {
    func load(transactionID: UUID) throws -> HelperInstallerTransactionJournal { throw NSError(domain: "stub", code: 1) }
}
struct HelperInstallerDescriptorFilesystemObserver {
    struct FileRecord: Equatable { let sha256: String }
    enum ArtifactState { case missing, present(FileRecord) }
    struct ReleasePointer: Equatable { let releaseIdentifier: String; let generation: UInt64 }
}
struct HelperInstallerArtifactReconciliationBackend {
    struct Result {
        let activeArtifacts: [HelperRootReleaseSet.Artifact: HelperInstallerDescriptorFilesystemObserver.ArtifactState]
        let stagedArtifacts: [HelperRootReleaseSet.Artifact: HelperInstallerDescriptorFilesystemObserver.ArtifactState]
        let previousArtifacts: [HelperRootReleaseSet.Artifact: HelperInstallerDescriptorFilesystemObserver.ArtifactState]
        let activeReleasePointer: HelperInstallerDescriptorFilesystemObserver.ReleasePointer?
        let activePointerMatchesObservedArtifacts: Bool
        let ownershipVerified: Bool
    }
    func observe(activePaths: [HelperRootReleaseSet.Artifact: String], stagedPaths: [HelperRootReleaseSet.Artifact: String], previousPaths: [HelperRootReleaseSet.Artifact: String]?) throws -> Result { throw NSError(domain: "stub", code: 1) }
}
struct HelperInstallerRecoveryCoordinator {
    enum Decision { case evidenceConsistentButExecutionNotAuthorized(next: String?), keepServiceStopped(reason: String) }
    struct Assessment { let decision: Decision }
    func assess(journal: HelperInstallerTransactionJournal, verifiedRelease: HelperRootReleaseSet.Verified,
                observation: HelperInstallerArtifactReconciliationBackend.Result,
                previousExpectedHashes: [HelperRootReleaseSet.Artifact: String]?) -> Assessment {
        .init(decision: .evidenceConsistentButExecutionNotAuthorized(next: nil))
    }
}
func check(_ condition: @autoclosure () -> Bool, _ label: String) {
    if !condition() { fatalError("FAIL: \(label)") }; print("PASS: \(label)")
}
let layout = try HelperInstallerRecoveryLayout(
    stagedRootRelativePath: "Library/FilterKit/Helper/Recovery/tx-1/staged",
    previousRootRelativePath: "Library/FilterKit/Helper/Recovery/tx-1/previous")
check(layout.activePaths[.executable] == HelperRootReleaseSet.executablePath, "active executable path is canonical")
check(layout.stagedPaths[.launchDaemon]?.hasSuffix("/cn.yfen.filterkit.helper.plist") == true, "staged launchd artifact path is explicit")
check(layout.previousPaths?.count == 3, "previous inventory contains exactly three artifacts")
do {
    _ = try HelperInstallerRecoveryLayout(stagedRootRelativePath: "Library/FilterKit/Helper/Recovery/x/staged", previousRootRelativePath: "Library/FilterKit/Helper/Recovery/x/staged/child")
    fatalError("overlapping roots accepted")
} catch HelperInstallerRecoveryLayout.LayoutError.overlappingRoots { check(true, "overlapping stage and previous roots rejected") }
do {
    _ = try HelperInstallerRecoveryLayout(stagedRootRelativePath: "../../tmp/stage", previousRootRelativePath: nil)
    fatalError("traversal accepted")
} catch HelperInstallerRecoveryLayout.LayoutError.unsafePath { check(true, "path traversal rejected") }
let observerHash = String(repeating: "a", count: 64)
let executableHash = String(repeating: "b", count: 64)
let validRunning = HelperInstallerServiceObservation(launchDaemonLabel: "cn.yfen.filterkit.helper", observerCodeIdentitySHA256: observerHash, state: .running(pid: 42, executableSHA256: executableHash))
check(validRunning.validates(expectedObserverCodeIdentitySHA256: observerHash, expectedExecutableSHA256: executableHash), "authenticated running service identity accepted")
check(!validRunning.validates(expectedObserverCodeIdentitySHA256: String(repeating: "c", count: 64), expectedExecutableSHA256: executableHash), "untrusted observer identity rejected")
let wrongLabel = HelperInstallerServiceObservation(launchDaemonLabel: "com.example.other", observerCodeIdentitySHA256: observerHash, state: .stopped)
check(!wrongLabel.validates(expectedObserverCodeIdentitySHA256: observerHash, expectedExecutableSHA256: executableHash), "wrong launchd label rejected")
let unknown = HelperInstallerServiceObservation(launchDaemonLabel: "cn.yfen.filterkit.helper", observerCodeIdentitySHA256: observerHash, state: .unknown)
check(!unknown.validates(expectedObserverCodeIdentitySHA256: observerHash, expectedExecutableSHA256: executableHash), "unknown service state rejected")
let stopped = HelperInstallerServiceObservation(launchDaemonLabel: "cn.yfen.filterkit.helper", observerCodeIdentitySHA256: observerHash, state: .stopped)
check(stopped.validates(expectedObserverCodeIdentitySHA256: observerHash, expectedExecutableSHA256: executableHash), "authenticated stopped service accepted")
let evidence = HelperInstallerRecoveryPreflight.Evidence(journalSequence: 7, journalHeadHash: observerHash,
    activeRecords: [:], stagedRecords: [:], previousRecords: [:], activePointer: nil,
    activePointerMatchesObservedArtifacts: false, ownershipVerified: true,
    serviceLabel: "cn.yfen.filterkit.helper", serviceObserverCodeIdentitySHA256: observerHash, serviceState: .stopped)
let changed = HelperInstallerRecoveryPreflight.Evidence(journalSequence: 8, journalHeadHash: observerHash,
    activeRecords: [:], stagedRecords: [:], previousRecords: [:], activePointer: nil,
    activePointerMatchesObservedArtifacts: false, ownershipVerified: true,
    serviceLabel: "cn.yfen.filterkit.helper", serviceObserverCodeIdentitySHA256: observerHash, serviceState: .stopped)
check(evidence != changed, "journal advancement changes evidence fingerprint")
let preflight = HelperInstallerRecoveryPreflight(journalStore: HelperInstallerDurableJournalStore(),
    reconciliationBackend: HelperInstallerArtifactReconciliationBackend(), layout: layout)
let rollbackJournal = HelperInstallerTransactionJournal(action: .upgrade, state: .rollbackRequired,
    pendingOperation: nil, sequence: 9, previousEventHash: observerHash)
let previousHashes: [HelperRootReleaseSet.Artifact: String] = [
    .executable: executableHash, .deploymentManifest: String(repeating: "c", count: 64),
    .launchDaemon: String(repeating: "d", count: 64)]
let previousStates: [HelperRootReleaseSet.Artifact: HelperInstallerDescriptorFilesystemObserver.ArtifactState] =
    Dictionary(uniqueKeysWithValues: previousHashes.map { ($0.key, .present(.init(sha256: $0.value))) })
try preflight.validateRollbackPrerequisites(journal: rollbackJournal, previousArtifacts: previousStates,
    previousExpectedHashes: previousHashes, service: stopped,
    expectedObserverCodeIdentitySHA256: observerHash)
check(true, "rollback requires verified complete previous inventory and stopped service")
do {
    try preflight.validateRollbackPrerequisites(journal: rollbackJournal,
        previousArtifacts: [.executable: .present(.init(sha256: executableHash))],
        previousExpectedHashes: previousHashes, service: stopped,
        expectedObserverCodeIdentitySHA256: observerHash)
    fatalError("incomplete rollback inventory accepted")
} catch HelperInstallerRecoveryPreflight.PreflightError.rollbackNotPermitted {
    check(true, "incomplete rollback inventory rejected")
}
let releaseHashes = previousHashes
let activeStates: [HelperRootReleaseSet.Artifact: HelperInstallerDescriptorFilesystemObserver.ArtifactState] =
    Dictionary(uniqueKeysWithValues: releaseHashes.map { ($0.key, .present(.init(sha256: $0.value))) })
let postRecovery = HelperInstallerArtifactReconciliationBackend.Result(activeArtifacts: activeStates,
    stagedArtifacts: [:], previousArtifacts: [:],
    activeReleasePointer: .init(releaseIdentifier: "previous-r", generation: 4),
    activePointerMatchesObservedArtifacts: true, ownershipVerified: true)
try preflight.validateRecoveredState(postRecovery, expectedHashes: releaseHashes,
    expectedReleaseIdentifier: "previous-r", expectedGeneration: 4, service: stopped,
    expectedObserverCodeIdentitySHA256: observerHash)
check(true, "post-recovery exact hashes, pointer, ownership, and stopped service accepted")
let badPostRecovery = HelperInstallerArtifactReconciliationBackend.Result(activeArtifacts: activeStates,
    stagedArtifacts: [:], previousArtifacts: [:],
    activeReleasePointer: .init(releaseIdentifier: "wrong", generation: 4),
    activePointerMatchesObservedArtifacts: true, ownershipVerified: true)
do {
    try preflight.validateRecoveredState(badPostRecovery, expectedHashes: releaseHashes,
        expectedReleaseIdentifier: "previous-r", expectedGeneration: 4, service: stopped,
        expectedObserverCodeIdentitySHA256: observerHash)
    fatalError("bad pointer accepted")
} catch HelperInstallerRecoveryPreflight.PreflightError.recoveredStateNotVerified {
    check(true, "post-recovery pointer identity mismatch rejected")
}
print("R14 preflight smoke: 14/14 assertions passed")
