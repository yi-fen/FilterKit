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
struct HelperInstallerDurableJournalStore {}
extension HelperInstallerDurableJournalStore {
    func save(_ journal: HelperInstallerTransactionJournal) throws {}
    func load(transactionID: UUID) throws -> HelperInstallerTransactionJournal { throw NSError(domain: "unused", code: 1) }
}
final class MemoryJournal: HelperInstallerJournalPersisting {
    var latest: HelperInstallerTransactionJournal?
    var saveCount = 0
    var failAtSave: Int?
    func save(_ journal: HelperInstallerTransactionJournal) throws {
        saveCount += 1
        if saveCount == failAtSave { throw NSError(domain: "injected-save", code: 1) }
        try journal.validateChain(); latest = journal
    }
    func load(transactionID: UUID) throws -> HelperInstallerTransactionJournal { guard let latest else { throw NSError(domain: "missing", code: 1) }; return latest }
}
final class Operations: HelperInstallerTransactionOperating {
    var calls: [String] = []
    var failStage = false
    func verifyArtifacts(_ prepared: HelperPreparedRootInstall) throws { calls.append("verify") }
    func preservePreviousRelease(_ prepared: HelperPreparedRootInstall) throws { calls.append("preserve") }
    func stageRelease(_ prepared: HelperPreparedRootInstall) throws { calls.append("stage"); if failStage { throw NSError(domain: "stage", code: 1) } }
    func activateRelease(_ prepared: HelperPreparedRootInstall) throws { calls.append("activate") }
    func verifyActivatedService(_ prepared: HelperPreparedRootInstall) throws { calls.append("service") }
    func rollback(_ prepared: HelperPreparedRootInstall, from state: HelperInstallerTransactionJournal.State) throws { calls.append("rollback") }
    func leaveServiceStopped(_ prepared: HelperPreparedRootInstall) throws { calls.append("stopped") }
}

func expect(_ condition: @autoclosure () -> Bool, _ label: String) {
    if !condition() { fatalError("FAIL: \(label)") }
    print("PASS: \(label)")
}
let store = MemoryJournal()
let ops = Operations()
var installJournal = try HelperInstallerTransactionJournal(action: .install, releaseIdentifier: "r10", generation: 10)
let installPrepared = HelperPreparedRootInstall(plan: .init(action: .install), initialJournal: installJournal)
let executor = HelperInstallerTransactionExecutor(journalStore: store, operations: ops)
let committed = try executor.execute(installPrepared) { .committed }
expect(committed.state == .committed, "install reaches committed")
expect(ops.calls == ["verify", "stage", "activate", "service"], "install operation order")
expect(store.latest?.state == .committed, "journal persisted at terminal state")

let rollbackStore = MemoryJournal()
let rollbackOps = Operations(); rollbackOps.failStage = true
let upgradeJournal = try HelperInstallerTransactionJournal(action: .upgrade, releaseIdentifier: "r10", generation: 10)
let upgradePrepared = HelperPreparedRootInstall(plan: .init(action: .upgrade), initialJournal: upgradeJournal)
let rollbackExecutor = HelperInstallerTransactionExecutor(journalStore: rollbackStore, operations: rollbackOps)
do {
    _ = try rollbackExecutor.execute(upgradePrepared) { .committed }
    fatalError("expected operation failure")
} catch let error as HelperInstallerTransactionExecutor.Failure {
    expect(error == .rollbackFailed, "interrupted operation requires reconciliation")
}
expect(rollbackStore.latest?.state == .manualIntervention, "pending stage intent escalates to manual recovery")
expect(rollbackStore.latest?.pendingOperation == .stageRelease, "stage intent retained after interruption")
expect(rollbackOps.calls.contains("preserve") && !rollbackOps.calls.contains("rollback") && rollbackOps.calls.contains("stopped"), "upgrade stops service without blind rollback while intent is pending")

var invalidJournal = try HelperInstallerTransactionJournal(action: .upgrade, releaseIdentifier: "r10", generation: 10)
try invalidJournal.apply(.intentVerifyArtifacts)
try invalidJournal.apply(.verifyArtifacts)
do { try invalidJournal.apply(.intentStageRelease); fatalError("expected invalid transition") }
catch { expect(true, "upgrade cannot skip previous release preservation") }

let commitStore = MemoryJournal(); commitStore.failAtSave = 11
let commitOps = Operations()
let commitPrepared = HelperPreparedRootInstall(plan: .init(action: .install),
    initialJournal: try HelperInstallerTransactionJournal(action: .install, releaseIdentifier: "r10", generation: 10))
let commitExecutor = HelperInstallerTransactionExecutor(journalStore: commitStore, operations: commitOps)
do {
    _ = try commitExecutor.execute(commitPrepared) { .committed }
    fatalError("expected indeterminate after durable commit journal failure")
} catch let error as HelperInstallerTransactionExecutor.Failure {
    expect(error == .provisioningCommitIndeterminate, "post-provisioning journal failure is indeterminate")
}
expect(commitOps.calls.contains("stopped"), "service stopped after uncertain commit")
expect(commitStore.latest?.state == .manualIntervention, "durable serviceVerified journal escalated to manual intervention")
