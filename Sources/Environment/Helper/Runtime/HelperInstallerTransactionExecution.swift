import Foundation

/// Persistence boundary used by the transaction driver. Production wiring must use the
/// root-owned HelperInstallerDurableJournalStore; tests may inject an in-memory implementation.
protocol HelperInstallerJournalPersisting {
    func save(_ journal: HelperInstallerTransactionJournal) throws
    func load(transactionID: UUID) throws -> HelperInstallerTransactionJournal
}

extension HelperInstallerDurableJournalStore: HelperInstallerJournalPersisting {}

/// Narrow operation boundary. A production implementation must use descriptor-relative,
/// ownership-checked operations and make every method idempotent. No production implementation
/// is provided in this phase.
protocol HelperInstallerTransactionOperating {
    func verifyArtifacts(_ prepared: HelperPreparedRootInstall) throws
    func preservePreviousRelease(_ prepared: HelperPreparedRootInstall) throws
    func stageRelease(_ prepared: HelperPreparedRootInstall) throws
    func activateRelease(_ prepared: HelperPreparedRootInstall) throws
    func verifyActivatedService(_ prepared: HelperPreparedRootInstall) throws
    func rollback(_ prepared: HelperPreparedRootInstall, from state: HelperInstallerTransactionJournal.State) throws
    func leaveServiceStopped(_ prepared: HelperPreparedRootInstall) throws
}

struct HelperUnavailableInstallerTransactionOperator: HelperInstallerTransactionOperating {
    enum Failure: Error { case unavailable }
    func verifyArtifacts(_ prepared: HelperPreparedRootInstall) throws { throw Failure.unavailable }
    func preservePreviousRelease(_ prepared: HelperPreparedRootInstall) throws { throw Failure.unavailable }
    func stageRelease(_ prepared: HelperPreparedRootInstall) throws { throw Failure.unavailable }
    func activateRelease(_ prepared: HelperPreparedRootInstall) throws { throw Failure.unavailable }
    func verifyActivatedService(_ prepared: HelperPreparedRootInstall) throws { throw Failure.unavailable }
    func rollback(_ prepared: HelperPreparedRootInstall, from state: HelperInstallerTransactionJournal.State) throws { throw Failure.unavailable }
    func leaveServiceStopped(_ prepared: HelperPreparedRootInstall) throws { throw Failure.unavailable }
}

enum HelperInstallerProvisioningCommitResult { case committed, rejected, indeterminate }

/// Adapter remains production-disabled until a separately reviewed privileged backend exists.
struct HelperJournaledRootInstallerAdapter: HelperRootInstallerExecuting {
    let journalStore: HelperInstallerJournalPersisting
    let operations: HelperInstallerTransactionOperating
    var isProductionReady: Bool { false }

    func execute(_ prepared: HelperPreparedRootInstall,
                 commitProvisioning: () throws -> HelperInstallerProvisioningCommitResult) throws {
        let executor = HelperInstallerTransactionExecutor(journalStore: journalStore, operations: operations)
        _ = try executor.execute(prepared, commitProvisioning: commitProvisioning)
    }
}

/// Journal-driven transaction engine. Every externally visible operation has a durable intent
/// before execution and a completion record afterwards. An interrupted intent is never blindly
/// rolled back; recovery must reconcile it against descriptor-verified filesystem observations.
struct HelperInstallerTransactionExecutor {
    enum Failure: Error, Equatable {
        case actionUnsupported
        case journalPersistenceFailed
        case operationFailed
        case rollbackFailed
        case provisioningCommitRejected
        case provisioningCommitIndeterminate
    }

    let journalStore: HelperInstallerJournalPersisting
    let operations: HelperInstallerTransactionOperating

    func execute(_ prepared: HelperPreparedRootInstall,
                 commitProvisioning: () throws -> HelperInstallerProvisioningCommitResult) throws -> HelperInstallerTransactionJournal {
        let action = prepared.plan.action
        guard action == .install || action == .upgrade || action == .repin else {
            throw Failure.actionUnsupported
        }
        var journal = prepared.initialJournal
        try persist(journal)
        do {
            try perform(&journal, intent: .intentVerifyArtifacts, completion: .verifyArtifacts) {
                try operations.verifyArtifacts(prepared)
            }
            if action == .upgrade || action == .repin {
                try perform(&journal, intent: .intentPreservePreviousRelease, completion: .preservePreviousRelease) {
                    try operations.preservePreviousRelease(prepared)
                }
            }
            try perform(&journal, intent: .intentStageRelease, completion: .stageRelease) {
                try operations.stageRelease(prepared)
            }
            try perform(&journal, intent: .intentActivateRelease, completion: .activateRelease) {
                try operations.activateRelease(prepared)
            }
            try perform(&journal, intent: .intentVerifyService, completion: .verifyService) {
                try operations.verifyActivatedService(prepared)
            }

            try advance(&journal, .intentCommitProvisioning)
            switch try commitProvisioning() {
            case .committed:
                do {
                    try advance(&journal, .commit)
                    return journal
                } catch {
                    // Provisioning is authoritative. Do not restore an older release against it.
                    try? operations.leaveServiceStopped(prepared)
                    if var durable = try? journalStore.load(transactionID: journal.transactionID),
                       durable.state == .serviceVerified {
                        try? durable.apply(.requireManualIntervention)
                        try? journalStore.save(durable)
                    }
                    throw Failure.provisioningCommitIndeterminate
                }
            case .rejected:
                try advance(&journal, .rejectCommitProvisioning)
                throw Failure.provisioningCommitRejected
            case .indeterminate:
                try advance(&journal, .requireManualIntervention)
                try operations.leaveServiceStopped(prepared)
                throw Failure.provisioningCommitIndeterminate
            }
        } catch let failure as Failure where failure == .provisioningCommitIndeterminate {
            throw failure
        } catch {
            // A pending intent means the side effect may have occurred before interruption or
            // completion persistence failure. Preserve it for reconciliation; do not guess.
            if journal.pendingOperation != nil {
                try? operations.leaveServiceStopped(prepared)
                if journal.state != .manualIntervention {
                    try? advance(&journal, .requireManualIntervention)
                }
                throw Failure.rollbackFailed
            }
            do {
                if journal.state != .committed && journal.state != .rolledBack && journal.state != .manualIntervention {
                    try advance(&journal, .beginRollback)
                    // Stop first so no service can execute while files are being restored.
                    try operations.leaveServiceStopped(prepared)
                    try operations.rollback(prepared, from: journal.state)
                    try advance(&journal, .completeRollback)
                }
            } catch {
                try? operations.leaveServiceStopped(prepared)
                if journal.state != .manualIntervention {
                    try? advance(&journal, .requireManualIntervention)
                }
                throw Failure.rollbackFailed
            }
            if error is Failure { throw error }
            throw Failure.operationFailed
        }
    }

    private func perform(_ journal: inout HelperInstallerTransactionJournal,
                         intent: HelperInstallerTransactionJournal.Event,
                         completion: HelperInstallerTransactionJournal.Event,
                         operation: () throws -> Void) throws {
        try advance(&journal, intent)
        let durableIntent = journal
        try operation()
        do {
            try advance(&journal, completion)
        } catch {
            // The operation may have succeeded even though its completion record did not persist.
            journal = durableIntent
            throw error
        }
    }

    private func advance(_ journal: inout HelperInstallerTransactionJournal,
                         _ event: HelperInstallerTransactionJournal.Event) throws {
        do {
            try journal.apply(event)
            try persist(journal)
        } catch {
            throw Failure.journalPersistenceFailed
        }
    }

    private func persist(_ journal: HelperInstallerTransactionJournal) throws {
        do { try journalStore.save(journal) }
        catch { throw Failure.journalPersistenceFailed }
    }
}
