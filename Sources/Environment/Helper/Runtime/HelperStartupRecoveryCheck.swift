import Foundation

/// Read-only startup gate for the legacy paired-file journal and P1-30 three-file journal.
/// Inspection never mutates TweakInject; a pending or invalid journal blocks normal IPC service.
struct HelperStartupRecoveryCheck {
    enum Detail: Equatable {
        case clean
        case legacyRecoveryRequired
        case threeFileRecoveryRequired
        case bothRecoveryRequired
        case invalidJournal
    }
    enum Result: Equatable { case clean, recoveryRequired, invalidJournal }

    func inspectDetailed(pluginDirectory: String) -> Detail {
        do {
            let legacyStore = try HelperTransactionJournalStore(directoryPath: pluginDirectory)
            let legacyPending: Bool
            if let journal = try legacyStore.load() {
                try journal.validate()
                legacyPending = true
            } else {
                legacyPending = false
            }
            let threeFilePending = try HelperThreeFileTransactionExecutor(directoryPath: pluginDirectory)
                .inspectPendingJournal()
            switch (legacyPending, threeFilePending) {
            case (false, false): return .clean
            case (true, false): return .legacyRecoveryRequired
            case (false, true): return .threeFileRecoveryRequired
            case (true, true): return .bothRecoveryRequired
            }
        } catch {
            return .invalidJournal
        }
    }

    func inspect(pluginDirectory: String) -> Result {
        switch inspectDetailed(pluginDirectory: pluginDirectory) {
        case .clean: return .clean
        case .legacyRecoveryRequired, .threeFileRecoveryRequired, .bothRecoveryRequired: return .recoveryRequired
        case .invalidJournal: return .invalidJournal
        }
    }
}

/// Explicit recovery entry point for a separately authorized maintenance action. It is not
/// called by HelperRuntime at startup. Legacy paired-file journals intentionally remain blocked
/// for the legacy recovery workflow; this coordinator only reconciles the P1-30 journal.
struct HelperAuthorizedRecoveryCoordinator {
    enum RecoveryError: Error, Equatable {
        case notRoot
        case legacyRecoveryRequiresDedicatedWorkflow
        case invalidJournal
        case recoveryIncomplete
    }

    @discardableResult
    func reconcileThreeFileTransaction(pluginDirectory: String) throws -> Bool {
        guard geteuid() == 0 else { throw RecoveryError.notRoot }
        let inspection = HelperStartupRecoveryCheck().inspectDetailed(pluginDirectory: pluginDirectory)
        switch inspection {
        case .clean: return false
        case .legacyRecoveryRequired, .bothRecoveryRequired:
            throw RecoveryError.legacyRecoveryRequiresDedicatedWorkflow
        case .invalidJournal:
            throw RecoveryError.invalidJournal
        case .threeFileRecoveryRequired:
            _ = try HelperThreeFileTransactionExecutor(directoryPath: pluginDirectory).reconcile()
            guard HelperStartupRecoveryCheck().inspectDetailed(pluginDirectory: pluginDirectory) == .clean else {
                throw RecoveryError.recoveryIncomplete
            }
            return true
        }
    }
}
