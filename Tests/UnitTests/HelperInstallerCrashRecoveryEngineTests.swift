import XCTest
@testable import FilterKit

final class HelperInstallerCrashRecoveryEngineTests: XCTestCase {
    private let targetHashes: [HelperRootReleaseSet.Artifact: String] = [
        .executable: String(repeating: "1", count: 64),
        .deploymentManifest: String(repeating: "2", count: 64),
        .launchDaemon: String(repeating: "3", count: 64)
    ]

    private func release() -> HelperRootReleaseSet.Verified {
        HelperRootReleaseSet.Verified(releaseIdentifier: "r11", generation: 11,
            hashes: targetHashes, byteCounts: [.executable: 10, .deploymentManifest: 20, .launchDaemon: 30])
    }

    private func snapshot(staged: [HelperRootReleaseSet.Artifact: String] = [:],
                          stagedID: String? = nil, activeID: String? = nil,
                          provisioning: String? = nil,
                          previousProvisioning: String? = nil,
                          previousHashes: [HelperRootReleaseSet.Artifact: String]? = nil,
                          previousPreserved: Bool = false,
                          previousOwned: Bool = false,
                          serviceRunning: Bool = false,
                          serviceIdentityMatches: Bool = false) -> HelperInstallerRecoverySnapshot {
        HelperInstallerRecoverySnapshot(stagedArtifactHashes: staged,
            artifactOwnershipVerified: true,
            previousReleasePreserved: previousPreserved,
            previousArtifactHashes: previousHashes,
            previousArtifactOwnershipVerified: previousOwned,
            stagedReleaseIdentifier: stagedID,
            activeReleaseIdentifier: activeID,
            serviceRunning: serviceRunning,
            serviceIdentityMatchesRelease: serviceIdentityMatches,
            provisioningEnvelopeSHA256: provisioning,
            previousProvisioningEnvelopeSHA256: previousProvisioning)
    }

    func testPendingStageCanBeRetriedOnlyWhenTargetIsAbsent() throws {
        var journal = try HelperInstallerTransactionJournal(action: .install,
            releaseIdentifier: "r11", generation: 11)
        try journal.apply(.intentVerifyArtifacts)
        try journal.apply(.verifyArtifacts)
        try journal.apply(.intentStageRelease)
        let result = HelperInstallerCrashRecoveryEngine().assess(journal: journal,
            release: release(), targetProvisioningSHA256: String(repeating: "a", count: 64),
            snapshot: snapshot())
        XCTAssertEqual(result.action, .retryIdempotentOperation(.stageRelease))
    }

    func testUnexpectedPartialArtifactSetRequiresManualIntervention() throws {
        var journal = try HelperInstallerTransactionJournal(action: .install,
            releaseIdentifier: "r11", generation: 11)
        try journal.apply(.intentVerifyArtifacts)
        try journal.apply(.verifyArtifacts)
        try journal.apply(.intentStageRelease)
        let partial = [.executable: String(repeating: "f", count: 64)]
        let result = HelperInstallerCrashRecoveryEngine().assess(journal: journal,
            release: release(), targetProvisioningSHA256: String(repeating: "a", count: 64),
            snapshot: snapshot(staged: partial))
        XCTAssertEqual(result.action, .stopServiceAndRequireManualIntervention)
    }

    func testAlreadyStagedReleaseCompletesIntent() throws {
        var journal = try HelperInstallerTransactionJournal(action: .install,
            releaseIdentifier: "r11", generation: 11)
        try journal.apply(.intentVerifyArtifacts); try journal.apply(.verifyArtifacts)
        try journal.apply(.intentStageRelease)
        let result = HelperInstallerCrashRecoveryEngine().assess(journal: journal,
            release: release(), targetProvisioningSHA256: String(repeating: "a", count: 64),
            snapshot: snapshot(staged: targetHashes, stagedID: "r11"))
        XCTAssertEqual(result.action, .recordCompletion(.stageRelease))
    }

    func testUpgradePreservationRequiresMatchingPreviousHashes() throws {
        var journal = try HelperInstallerTransactionJournal(action: .upgrade,
            releaseIdentifier: "r11", generation: 11)
        try journal.apply(.intentVerifyArtifacts); try journal.apply(.verifyArtifacts)
        try journal.apply(.intentPreservePreviousRelease)
        let previous: [HelperRootReleaseSet.Artifact: String] = [
            .executable: String(repeating: "4", count: 64),
            .deploymentManifest: String(repeating: "5", count: 64),
            .launchDaemon: String(repeating: "6", count: 64)
        ]
        let result = HelperInstallerCrashRecoveryEngine().assess(journal: journal,
            release: release(), targetProvisioningSHA256: String(repeating: "a", count: 64),
            previousReleaseHashes: previous,
            snapshot: snapshot(staged: targetHashes, previousHashes: previous, previousOwned: true))
        XCTAssertEqual(result.action, .retryIdempotentOperation(.preservePreviousRelease))
    }

    func testProvisioningAlreadyCommittedIsNotReplayed() throws {
        var journal = try HelperInstallerTransactionJournal(action: .install,
            releaseIdentifier: "r11", generation: 11)
        try journal.apply(.intentVerifyArtifacts); try journal.apply(.verifyArtifacts)
        try journal.apply(.intentStageRelease); try journal.apply(.stageRelease)
        try journal.apply(.intentActivateRelease); try journal.apply(.activateRelease)
        try journal.apply(.intentVerifyService); try journal.apply(.verifyService)
        try journal.apply(.intentCommitProvisioning)
        let envelope = String(repeating: "b", count: 64)
        let result = HelperInstallerCrashRecoveryEngine().assess(journal: journal,
            release: release(), targetProvisioningSHA256: envelope,
            snapshot: snapshot(staged: targetHashes, stagedID: "r11", activeID: "r11",
                provisioning: envelope, serviceIdentityMatches: true))
        XCTAssertEqual(result.action, .recordCompletion(.commit))
    }
    func testDurableCompletedStepBeginsNextIntent() throws {
        var journal = try HelperInstallerTransactionJournal(action: .install,
            releaseIdentifier: "r11", generation: 11)
        try journal.apply(.intentVerifyArtifacts)
        try journal.apply(.verifyArtifacts)
        let result = HelperInstallerCrashRecoveryEngine().assess(journal: journal,
            release: release(), targetProvisioningSHA256: String(repeating: "a", count: 64),
            snapshot: snapshot())
        XCTAssertEqual(result.action, .beginNextOperation(.stageRelease))
    }

}
