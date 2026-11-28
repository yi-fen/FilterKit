import Foundation

/// Read-only journal-level crash assessment. Filesystem reconciliation is performed separately by
/// HelperInstallerCrashRecoveryEngine after a privileged observer collects descriptor-verified facts.
struct HelperInstallerRecoveryAssessment: Equatable {
    enum Recommendation: Equatable {
        case noActionRequired, resumeVerification, restorePreviousRelease
        case verifyActivatedRelease, finalizeCommit, confirmRollback, manualIntervention
        case reconcilePendingOperation(HelperInstallerTransactionJournal.PendingOperation)
        case beginNextOperation(HelperInstallerTransactionJournal.PendingOperation)
    }

    let transactionID: UUID
    let state: HelperInstallerTransactionJournal.State
    let recommendation: Recommendation

    static func assess(_ journal: HelperInstallerTransactionJournal) throws -> Self {
        do { try journal.validateChain() } catch { throw HelperInstallerTransactionJournal.JournalError.corruptChain }
        let recommendation: Recommendation
        if journal.state == .manualIntervention {
            recommendation = .manualIntervention
        } else if let pending = journal.pendingOperation {
            recommendation = .reconcilePendingOperation(pending)
        } else {
            switch journal.state {
            case .prepared: recommendation = .beginNextOperation(.verifyArtifacts)
            case .artifactsVerified:
                recommendation = .beginNextOperation((journal.action == .upgrade || journal.action == .repin) ? .preservePreviousRelease : .stageRelease)
            case .previousReleasePreserved: recommendation = .beginNextOperation(.stageRelease)
            case .staged: recommendation = .beginNextOperation(.activateRelease)
            case .activated: recommendation = .beginNextOperation(.verifyService)
            case .serviceVerified: recommendation = .beginNextOperation(.commitProvisioning)
            case .committed: recommendation = .noActionRequired
            case .rollbackRequired: recommendation = .confirmRollback
            case .rolledBack: recommendation = .noActionRequired
            case .manualIntervention: recommendation = .manualIntervention
            }
        }
        return Self(transactionID: journal.transactionID, state: journal.state, recommendation: recommendation)
    }
}
