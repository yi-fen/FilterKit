import XCTest
@testable import FilterKit

final class HelperSafeFileExecutorTests: XCTestCase {
    func testOwnershipProofRequiresSchemaThreeAndBinaryIdentity() throws {
        XCTAssertThrowsError(try HelperOwnershipProof(pluginID: UUID(), dylibFileName: "A.dylib",
            plistFileName: "A.plist", dylibSHA256: String(repeating: "a", count: 64),
            plistSHA256: String(repeating: "b", count: 64), manifestSchemaVersion: 2,
            manifestSHA256: String(repeating: "c", count: 64), binaryIdentityVerified: true))
        XCTAssertThrowsError(try HelperOwnershipProof(pluginID: UUID(), dylibFileName: "A.dylib",
            plistFileName: "A.plist", dylibSHA256: String(repeating: "a", count: 64),
            plistSHA256: String(repeating: "b", count: 64), manifestSchemaVersion: 3,
            manifestSHA256: String(repeating: "c", count: 64), binaryIdentityVerified: false))
    }

    func testOwnershipProofRejectsUnsafeNamesAndHashes() {
        XCTAssertThrowsError(try HelperOwnershipProof(pluginID: UUID(), dylibFileName: "../A.dylib",
            plistFileName: "A.plist", dylibSHA256: String(repeating: "a", count: 64),
            plistSHA256: String(repeating: "b", count: 64), manifestSchemaVersion: 3,
            manifestSHA256: String(repeating: "c", count: 64), binaryIdentityVerified: true))
    }

    func testRemovalIsStillDeniedWithoutOwnershipProofPath() throws {
        let manifest = HelperDeploymentManifest.disabledTemplate(routeIdentifier: "roothide",
            jbRootPath: "/var/jb", tweakInjectPath: "/var/jb/usr/lib/TweakInject",
            stagingRootPath: "/var/mobile/Library/FilterKit/Staging",
            socketPath: "/var/jb/Library/FilterKit/Helper/helper.sock")
        let request = HelperOperationRequest(requestID: UUID(), operation: .removeUnmanagedDylib,
            pluginID: UUID(), stagingRelativePath: nil, targetFileName: "A.dylib",
            expectedSHA256: nil, createdAt: Date())
        let peer = HelperPeerIdentity(uid: 501, gid: 501, pid: 10,
            cdHashHex: String(repeating: "a", count: 40), pidVersion: nil, auditSessionID: nil)
        XCTAssertThrowsError(try HelperPolicy().authorize(request, peer: peer,
            helperCDHashHex: String(repeating: "b", count: 40), manifest: manifest,
            targetExists: true, sourceIsRegularNonSymlink: true, sourceHashMatches: true))
    }

    func testExecutionRemainsUnreleased() {
        XCTAssertFalse(HelperDeploymentCoordinator.executionReleased)
    }
}

final class HelperTransactionRecoveryTests: XCTestCase {
    func testInterruptedDylibCommitPlansExactRollback() throws {
        let transactionID = UUID()
        let oldHash = String(repeating: "a", count: 64)
        let dylibHash = String(repeating: "b", count: 64)
        let plistHash = String(repeating: "c", count: 64)
        let journal = try HelperTransactionJournal(transactionID: transactionID, pluginID: UUID(),
            dylibFileName: "Demo.dylib", plistFileName: "Demo.plist", dylibSHA256: dylibHash,
            plistSHA256: plistHash, previousPlistSHA256: oldHash, phase: .installingPlist)
        let observed = HelperTransactionFileObservation(temporaryDylibHash: nil,
            temporaryPlistHash: plistHash, deployedDylibHash: dylibHash,
            deployedPlistHash: nil, previousPlistHash: oldHash)
        let actions = try HelperTransactionRecoveryPlanner().plan(journal: journal, observed: observed)
        XCTAssertTrue(actions.contains(.removeDeployedDylib("Demo.dylib", expectedSHA256: dylibHash)))
        XCTAssertTrue(actions.contains(.restorePreviousPlist(backup: journal.previousPlistName,
            destination: "Demo.plist", expectedSHA256: oldHash)))
        XCTAssertTrue(actions.contains(.removeTemporaryPlist(journal.temporaryPlistName, expectedSHA256: plistHash)))
        XCTAssertEqual(actions.last, .clearJournal)
    }

    func testCommittedTransactionOnlyCleansVerifiedBackup() throws {
        let oldHash = String(repeating: "a", count: 64)
        let dylibHash = String(repeating: "b", count: 64)
        let plistHash = String(repeating: "c", count: 64)
        let journal = try HelperTransactionJournal(transactionID: UUID(), pluginID: UUID(),
            dylibFileName: "Demo.dylib", plistFileName: "Demo.plist", dylibSHA256: dylibHash,
            plistSHA256: plistHash, previousPlistSHA256: oldHash, phase: .committed)
        let observed = HelperTransactionFileObservation(temporaryDylibHash: nil,
            temporaryPlistHash: nil, deployedDylibHash: dylibHash,
            deployedPlistHash: plistHash, previousPlistHash: oldHash)
        let actions = try HelperTransactionRecoveryPlanner().plan(journal: journal, observed: observed)
        XCTAssertEqual(actions, [.removePreviousPlist(journal.previousPlistName, expectedSHA256: oldHash), .clearJournal])
    }

    func testRecoveryRejectsForeignPlistEvenWhenBackupMatches() throws {
        let oldHash = String(repeating: "a", count: 64)
        let journal = try HelperTransactionJournal(transactionID: UUID(), pluginID: UUID(),
            dylibFileName: "Demo.dylib", plistFileName: "Demo.plist",
            dylibSHA256: String(repeating: "b", count: 64),
            plistSHA256: String(repeating: "c", count: 64), previousPlistSHA256: oldHash,
            phase: .installingPlist)
        let observed = HelperTransactionFileObservation(temporaryDylibHash: nil,
            temporaryPlistHash: nil, deployedDylibHash: nil,
            deployedPlistHash: String(repeating: "d", count: 64), previousPlistHash: oldHash)
        XCTAssertEqual(try HelperTransactionRecoveryPlanner().plan(journal: journal, observed: observed), [.manualIntervention])
    }

    func testRecoveryRequiresRecordedPreviousPlistToRemainRecoverable() throws {
        let oldHash = String(repeating: "a", count: 64)
        let journal = try HelperTransactionJournal(transactionID: UUID(), pluginID: UUID(),
            dylibFileName: "Demo.dylib", plistFileName: "Demo.plist",
            dylibSHA256: String(repeating: "b", count: 64),
            plistSHA256: String(repeating: "c", count: 64), previousPlistSHA256: oldHash,
            phase: .installingPlist)
        let observed = HelperTransactionFileObservation(temporaryDylibHash: nil,
            temporaryPlistHash: nil, deployedDylibHash: nil,
            deployedPlistHash: nil, previousPlistHash: nil)
        XCTAssertEqual(try HelperTransactionRecoveryPlanner().plan(journal: journal, observed: observed), [.manualIntervention])
    }

    func testRecoveryRejectsForeignObservedBytes() throws {
        let journal = try HelperTransactionJournal(transactionID: UUID(), pluginID: UUID(),
            dylibFileName: "Demo.dylib", plistFileName: "Demo.plist",
            dylibSHA256: String(repeating: "b", count: 64),
            plistSHA256: String(repeating: "c", count: 64), previousPlistSHA256: nil)
        let observed = HelperTransactionFileObservation(temporaryDylibHash: nil,
            temporaryPlistHash: nil, deployedDylibHash: String(repeating: "d", count: 64),
            deployedPlistHash: nil, previousPlistHash: nil)
        XCTAssertEqual(try HelperTransactionRecoveryPlanner().plan(journal: journal, observed: observed), [.manualIntervention])
    }
}
