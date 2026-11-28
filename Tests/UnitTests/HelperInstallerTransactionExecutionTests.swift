import XCTest
@testable import FilterKit

final class HelperInstallerTransactionExecutionTests: XCTestCase {
    func testProvisioningCommitRejectionCanRollbackAfterServiceVerification() throws {
        var journal = try HelperInstallerTransactionJournal(action: .upgrade,
            releaseIdentifier: "r10", generation: 10)
        try journal.apply(.intentVerifyArtifacts); try journal.apply(.verifyArtifacts)
        try journal.apply(.intentPreservePreviousRelease); try journal.apply(.preservePreviousRelease)
        try journal.apply(.intentStageRelease); try journal.apply(.stageRelease)
        try journal.apply(.intentActivateRelease); try journal.apply(.activateRelease)
        try journal.apply(.intentVerifyService); try journal.apply(.verifyService)
        try journal.apply(.intentCommitProvisioning)
        try journal.apply(.rejectCommitProvisioning)
        try journal.apply(.beginRollback)
        try journal.apply(.completeRollback)
        try journal.validateChain()
        XCTAssertEqual(journal.state, .rolledBack)
    }

    func testProvisioningCommitIndeterminateCanBeJournaledAsManualIntervention() throws {
        var journal = try HelperInstallerTransactionJournal(action: .install,
            releaseIdentifier: "r10", generation: 10)
        try journal.apply(.intentVerifyArtifacts); try journal.apply(.verifyArtifacts)
        try journal.apply(.intentStageRelease); try journal.apply(.stageRelease)
        try journal.apply(.intentActivateRelease); try journal.apply(.activateRelease)
        try journal.apply(.intentVerifyService); try journal.apply(.verifyService)
        try journal.apply(.intentCommitProvisioning)
        try journal.apply(.requireManualIntervention)
        try journal.validateChain()
        XCTAssertEqual(journal.state, .manualIntervention)
    }

    func testUpgradeCannotSkipPreservingPreviousRelease() throws {
        var journal = try HelperInstallerTransactionJournal(action: .upgrade,
            releaseIdentifier: "r10", generation: 10)
        try journal.apply(.intentVerifyArtifacts)
        try journal.apply(.verifyArtifacts)
        XCTAssertThrowsError(try journal.apply(.intentStageRelease))
    }
}
