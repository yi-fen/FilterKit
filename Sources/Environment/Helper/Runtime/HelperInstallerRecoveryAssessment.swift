import Foundation

/// Read-only crash-recovery assessment. It recommends an operator/recovery path but never mutates files.
struct HelperInstallerRecoveryAssessment: Equatable {
    enum Recommendation: Equatable {
        case noActionRequired, resumeVerification, restorePreviousRelease
        case verifyActivatedRelease, finalizeCommit, confirmRollback, manualIntervention
    }

    let transactionID: UUID
    let state: HelperInstallerTransactionJournal.State
    let recommendation: Recommendation

    static func assess(_ journal: HelperInstallerTransactionJournal) throws -> Self {
        do { try journal.validateChain() } catch { throw HelperInstallerTransactionJournal.JournalError.corruptChain }
        let recommendation: Recommendation
        switch journal.state {
        case .prepared: recommendation = .resumeVerification
        case .artifactsVerified: recommendation = journal.action == .install ? .resumeVerification : .restorePreviousRelease
        case .previousReleasePreserved: recommendation = .restorePreviousRelease
        case .staged: recommendation = journal.action == .install ? .verifyActivatedRelease : .restorePreviousRelease
        case .activated: recommendation = .verifyActivatedRelease
        case .serviceVerified: recommendation = .finalizeCommit
        case .committed: recommendation = .noActionRequired
        case .rollbackRequired: recommendation = .confirmRollback
        case .rolledBack: recommendation = .noActionRequired
        case .manualIntervention: recommendation = .manualIntervention
        }
        return Self(transactionID: journal.transactionID, state: journal.state, recommendation: recommendation)
    }
}
