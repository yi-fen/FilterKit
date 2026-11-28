import Foundation

enum HelperPolicy {
    static func isValidHash(_ value: String) -> Bool {
        value.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil
    }
}
struct HelperInstallerTransactionPlan {
    enum Action: String, Codable { case install, upgrade, repin, start, stop, uninstall }
    let action: Action
}
struct HelperPreparedRootInstall {
    let plan: HelperInstallerTransactionPlan
    let initialJournal: HelperInstallerTransactionJournal
}
protocol HelperRootInstallerExecuting {
    var isProductionReady: Bool { get }
    func execute(_ prepared: HelperPreparedRootInstall,
                 commitProvisioning: () throws -> HelperInstallerProvisioningCommitResult) throws
}
struct HelperRootReleaseSet {
    enum Artifact: String, CaseIterable, Hashable { case executable, deploymentManifest, launchDaemon }
    struct Verified {
        let releaseIdentifier: String
        let generation: UInt64
        let hashes: [Artifact: String]
        let byteCounts: [Artifact: Int]
    }
}
final class MemoryJournal: HelperInstallerJournalPersisting {
    var latest: HelperInstallerTransactionJournal?
    var saveCount = 0
    var failAtSave: Int?
    func save(_ journal: HelperInstallerTransactionJournal) throws {
        saveCount += 1
        if saveCount == failAtSave { throw NSError(domain: "injected-save", code: 1) }
        try journal.validateChain()
        latest = journal
    }
    func load(transactionID: UUID) throws -> HelperInstallerTransactionJournal {
        guard let latest, latest.transactionID == transactionID else { throw NSError(domain: "missing", code: 1) }
        return latest
    }
}
final class Operations: HelperInstallerTransactionOperating {
    let store: MemoryJournal
    var calls: [String] = []
    var failStageAfterSideEffect = false
    init(store: MemoryJournal) { self.store = store }
    func verifyArtifacts(_ prepared: HelperPreparedRootInstall) throws {
        expect(store.latest?.pendingOperation == .verifyArtifacts, "verify intent persisted before side effect")
        calls.append("verify")
    }
    func preservePreviousRelease(_ prepared: HelperPreparedRootInstall) throws { calls.append("preserve") }
    func stageRelease(_ prepared: HelperPreparedRootInstall) throws {
        expect(store.latest?.pendingOperation == .stageRelease, "stage intent persisted before side effect")
        calls.append("stage")
        if failStageAfterSideEffect { throw NSError(domain: "crash-window", code: 1) }
    }
    func activateRelease(_ prepared: HelperPreparedRootInstall) throws { calls.append("activate") }
    func verifyActivatedService(_ prepared: HelperPreparedRootInstall) throws { calls.append("service") }
    func rollback(_ prepared: HelperPreparedRootInstall, from state: HelperInstallerTransactionJournal.State) throws { calls.append("rollback") }
    func leaveServiceStopped(_ prepared: HelperPreparedRootInstall) throws { calls.append("stopped") }
}
func expect(_ condition: @autoclosure () -> Bool, _ label: String) {
    if !condition() { fatalError("FAIL: \(label)") }
    print("PASS: \(label)")
}

let hashes: [HelperRootReleaseSet.Artifact: String] = [
    .executable: String(repeating: "1", count: 64),
    .deploymentManifest: String(repeating: "2", count: 64),
    .launchDaemon: String(repeating: "3", count: 64)
]
let verified = HelperRootReleaseSet.Verified(releaseIdentifier: "r11", generation: 11,
    hashes: hashes, byteCounts: [.executable: 100, .deploymentManifest: 200, .launchDaemon: 300])

// A full successful install records an intent before every externally visible operation.
let successStore = MemoryJournal()
let successOps = Operations(store: successStore)
let successPrepared = HelperPreparedRootInstall(
    plan: .init(action: .install),
    initialJournal: try HelperInstallerTransactionJournal(action: .install, releaseIdentifier: "r11", generation: 11))
let successExecutor = HelperInstallerTransactionExecutor(journalStore: successStore, operations: successOps)
let completed = try successExecutor.execute(successPrepared) { .committed }
expect(completed.state == .committed && completed.pendingOperation == nil, "successful install commits with no pending intent")
expect(successStore.latest?.state == .committed, "terminal commit is durable")

// A crash/error after the stage side effect but before its completion record must not trigger blind rollback.
let crashStore = MemoryJournal()
let crashOps = Operations(store: crashStore); crashOps.failStageAfterSideEffect = true
let crashPrepared = HelperPreparedRootInstall(
    plan: .init(action: .install),
    initialJournal: try HelperInstallerTransactionJournal(action: .install, releaseIdentifier: "r11", generation: 11))
let crashExecutor = HelperInstallerTransactionExecutor(journalStore: crashStore, operations: crashOps)
do {
    _ = try crashExecutor.execute(crashPrepared) { .committed }
    fatalError("expected injected stage interruption")
} catch let error as HelperInstallerTransactionExecutor.Failure {
    expect(error == .rollbackFailed, "interrupted operation is surfaced as recovery-required")
}
expect(crashStore.latest?.state == .manualIntervention, "interrupted operation is marked manual")
expect(crashStore.latest?.pendingOperation == .stageRelease, "pending stage intent is retained for reconciliation")
expect(!crashOps.calls.contains("rollback") && crashOps.calls.contains("stopped"), "no blind rollback; service is stopped")

// Reconcile a pending stage intent from a trusted filesystem snapshot.
var pendingJournal = try HelperInstallerTransactionJournal(action: .install, releaseIdentifier: "r11", generation: 11)
try pendingJournal.apply(.intentVerifyArtifacts)
try pendingJournal.apply(.verifyArtifacts)
try pendingJournal.apply(.intentStageRelease)
try pendingJournal.validateChain()
let journalOnlyAssessment = try HelperInstallerRecoveryAssessment.assess(pendingJournal)
expect(journalOnlyAssessment.recommendation == .reconcilePendingOperation(.stageRelease), "journal-only assessment exposes pending operation")
let snapshot = HelperInstallerRecoverySnapshot(
    stagedArtifactHashes: hashes, artifactOwnershipVerified: true,
    previousReleasePreserved: false, previousArtifactHashes: nil,
    previousArtifactOwnershipVerified: false, stagedReleaseIdentifier: "r11",
    activeReleaseIdentifier: nil, serviceRunning: false,
    serviceIdentityMatchesRelease: false, provisioningEnvelopeSHA256: nil,
    previousProvisioningEnvelopeSHA256: nil)
let assessment = HelperInstallerCrashRecoveryEngine().assess(
    journal: pendingJournal, release: verified,
    targetProvisioningSHA256: String(repeating: "a", count: 64), snapshot: snapshot)
expect(assessment.action == .recordCompletion(.stageRelease), "filesystem evidence completes already-staged operation")
let absentStageSnapshot = HelperInstallerRecoverySnapshot(
    stagedArtifactHashes: [:], artifactOwnershipVerified: true,
    previousReleasePreserved: false, previousArtifactHashes: nil,
    previousArtifactOwnershipVerified: false, stagedReleaseIdentifier: nil,
    activeReleaseIdentifier: nil, serviceRunning: false,
    serviceIdentityMatchesRelease: false, provisioningEnvelopeSHA256: nil,
    previousProvisioningEnvelopeSHA256: nil)
let absentStageAssessment = HelperInstallerCrashRecoveryEngine().assess(
    journal: pendingJournal, release: verified,
    targetProvisioningSHA256: String(repeating: "a", count: 64), snapshot: absentStageSnapshot)
expect(absentStageAssessment.action == .retryIdempotentOperation(.stageRelease), "absent stage can be retried idempotently")
var completedVerifyJournal = try HelperInstallerTransactionJournal(action: .install, releaseIdentifier: "r11", generation: 11)
try completedVerifyJournal.apply(.intentVerifyArtifacts)
try completedVerifyJournal.apply(.verifyArtifacts)
let nextOperationAssessment = HelperInstallerCrashRecoveryEngine().assess(
    journal: completedVerifyJournal, release: verified,
    targetProvisioningSHA256: String(repeating: "a", count: 64), snapshot: absentStageSnapshot)
expect(nextOperationAssessment.action == .beginNextOperation(.stageRelease), "durable completion begins next intent before operation")

// Unexpected artifact bytes fail closed even when the journal itself is valid.
let badSnapshot = HelperInstallerRecoverySnapshot(
    stagedArtifactHashes: [.executable: String(repeating: "f", count: 64),
                           .deploymentManifest: hashes[.deploymentManifest]!,
                           .launchDaemon: hashes[.launchDaemon]!],
    artifactOwnershipVerified: true, previousReleasePreserved: false,
    previousArtifactHashes: nil, previousArtifactOwnershipVerified: false,
    stagedReleaseIdentifier: "r11", activeReleaseIdentifier: nil,
    serviceRunning: false, serviceIdentityMatchesRelease: false,
    provisioningEnvelopeSHA256: nil, previousProvisioningEnvelopeSHA256: nil)
let badAssessment = HelperInstallerCrashRecoveryEngine().assess(
    journal: pendingJournal, release: verified,
    targetProvisioningSHA256: String(repeating: "a", count: 64), snapshot: badSnapshot)
expect(badAssessment.action == .stopServiceAndRequireManualIntervention, "unexpected artifact hash requires manual intervention")

// Provisioning commit already present is reconciled by recording completion, not re-running commit.
var commitJournal = try HelperInstallerTransactionJournal(action: .install, releaseIdentifier: "r11", generation: 11)
try commitJournal.apply(.intentVerifyArtifacts); try commitJournal.apply(.verifyArtifacts)
try commitJournal.apply(.intentStageRelease); try commitJournal.apply(.stageRelease)
try commitJournal.apply(.intentActivateRelease); try commitJournal.apply(.activateRelease)
try commitJournal.apply(.intentVerifyService); try commitJournal.apply(.verifyService)
try commitJournal.apply(.intentCommitProvisioning)
let targetEnvelope = String(repeating: "b", count: 64)
let commitSnapshot = HelperInstallerRecoverySnapshot(
    stagedArtifactHashes: hashes, artifactOwnershipVerified: true,
    previousReleasePreserved: false, previousArtifactHashes: nil,
    previousArtifactOwnershipVerified: false, stagedReleaseIdentifier: "r11",
    activeReleaseIdentifier: "r11", serviceRunning: false,
    serviceIdentityMatchesRelease: true, provisioningEnvelopeSHA256: targetEnvelope,
    previousProvisioningEnvelopeSHA256: String(repeating: "c", count: 64))
let commitAssessment = HelperInstallerCrashRecoveryEngine().assess(
    journal: commitJournal, release: verified, targetProvisioningSHA256: targetEnvelope,
    snapshot: commitSnapshot)
expect(commitAssessment.action == .recordCompletion(.commit), "already-committed provisioning is reconciled without replay")

var upgradeJournal = try HelperInstallerTransactionJournal(action: .upgrade, releaseIdentifier: "r11", generation: 11)
try upgradeJournal.apply(.intentVerifyArtifacts); try upgradeJournal.apply(.verifyArtifacts)
try upgradeJournal.apply(.intentPreservePreviousRelease)
let previousHashes: [HelperRootReleaseSet.Artifact: String] = [
    .executable: String(repeating: "4", count: 64),
    .deploymentManifest: String(repeating: "5", count: 64),
    .launchDaemon: String(repeating: "6", count: 64)
]
let preserveSnapshot = HelperInstallerRecoverySnapshot(
    stagedArtifactHashes: hashes, artifactOwnershipVerified: true,
    previousReleasePreserved: false, previousArtifactHashes: previousHashes,
    previousArtifactOwnershipVerified: true, stagedReleaseIdentifier: nil,
    activeReleaseIdentifier: nil, serviceRunning: false,
    serviceIdentityMatchesRelease: false, provisioningEnvelopeSHA256: nil,
    previousProvisioningEnvelopeSHA256: String(repeating: "c", count: 64))
let preserveAssessment = HelperInstallerCrashRecoveryEngine().assess(
    journal: upgradeJournal, release: verified,
    targetProvisioningSHA256: String(repeating: "a", count: 64),
    previousReleaseHashes: previousHashes, snapshot: preserveSnapshot)
expect(preserveAssessment.action == .retryIdempotentOperation(.preservePreviousRelease), "upgrade preservation retries only with verified previous hashes")
print("R11 crash-recovery smoke: 17/17 assertions passed")
