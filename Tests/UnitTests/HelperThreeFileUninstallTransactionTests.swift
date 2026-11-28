import XCTest
@testable import FilterKit
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

final class HelperThreeFileUninstallTransactionTests: XCTestCase {
    private struct Fixture {
        let directory: URL
        let proof: HelperOwnershipProof
    }

    private func makeFixture() throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FilterKitUninstall-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        _ = chmod(directory.path, 0o700)
        let dylib = Data("fixture-macho-payload".utf8)
        let plist = Data("<?xml version=\"1.0\"?><plist version=\"1.0\"><dict/></plist>".utf8)
        let manifest = Data("verified-root-owned-manifest-fixture".utf8)
        try dylib.write(to: directory.appendingPathComponent("Example.dylib"))
        try plist.write(to: directory.appendingPathComponent("Example.plist"))
        try manifest.write(to: directory.appendingPathComponent("Example.fk.json"))
        _ = chmod(directory.appendingPathComponent("Example.dylib").path, 0o644)
        _ = chmod(directory.appendingPathComponent("Example.plist").path, 0o644)
        _ = chmod(directory.appendingPathComponent("Example.fk.json").path, 0o600)
        let proof = try HelperOwnershipProof(pluginID: UUID(), dylibFileName: "Example.dylib",
            plistFileName: "Example.plist", dylibSHA256: SHA256Digest.hex(dylib),
            plistSHA256: SHA256Digest.hex(plist), manifestSchemaVersion: 3,
            manifestSHA256: SHA256Digest.hex(manifest), binaryIdentityVerified: true,
            machOIdentitySHA256: String(repeating: "a", count: 64),
            hardBoundBundleIdentifier: "com.example.owner", softAssociations: [])
        return Fixture(directory: directory, proof: proof)
    }

    private func requireRoot() throws {
        guard geteuid() == 0 else { throw XCTSkip("Root-only filesystem transaction test") }
    }

    func testSuccessfulUninstallRemovesAllThreeVerifiedFiles() throws {
        try requireRoot()
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let transaction = try HelperThreeFileUninstallTransaction(directoryPath: fixture.directory.path)
        let receipt = try transaction.execute(proof: fixture.proof)
        XCTAssertEqual(receipt.pluginID, fixture.proof.pluginID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("Example.dylib").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("Example.plist").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("Example.fk.json").path))
        XCTAssertFalse(try transaction.inspectPendingJournal())
    }

    func testPreCommitCrashCanRollbackAllThreeFiles() throws {
        try requireRoot()
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let transaction = try HelperThreeFileUninstallTransaction(directoryPath: fixture.directory.path)
        let transactionID = UUID()
        XCTAssertThrowsError(try transaction.execute(proof: fixture.proof, transactionID: transactionID,
            simulateCrashAfter: .movingPlist))
        XCTAssertTrue(try transaction.inspectPendingJournal())
        _ = try transaction.reconcile(expectedTransactionID: transactionID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("Example.dylib").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("Example.plist").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("Example.fk.json").path))
        XCTAssertFalse(try transaction.inspectPendingJournal())
    }

    func testPostCommitCrashCompletesDeletionDuringRecovery() throws {
        try requireRoot()
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let transaction = try HelperThreeFileUninstallTransaction(directoryPath: fixture.directory.path)
        let transactionID = UUID()
        XCTAssertThrowsError(try transaction.execute(proof: fixture.proof, transactionID: transactionID,
            simulateCrashAfter: .committed))
        _ = try transaction.reconcile(expectedTransactionID: transactionID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("Example.dylib").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("Example.plist").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("Example.fk.json").path))
        XCTAssertFalse(try transaction.inspectPendingJournal())
    }

    func testUninstallRemovesPluginForAllTargetsEvenWhenConfiguredEnabled() throws {
        try requireRoot()
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let transaction = try HelperThreeFileUninstallTransaction(directoryPath: fixture.directory.path)
        _ = try transaction.execute(proof: fixture.proof)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("Example.dylib").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("Example.plist").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("Example.fk.json").path))
    }

    func testEveryUninstallJournalPhaseRecoversToOneConsistentOutcome() throws {
        let phases: [HelperThreeFileUninstallTransaction.Phase] = [
            .prepared, .movingDylib, .movingPlist, .movingManifest, .committed
        ]
        for phase in phases {
            try requireRoot()
            let fixture = try makeFixture()
            defer { try? FileManager.default.removeItem(at: fixture.directory) }
            let transaction = try HelperThreeFileUninstallTransaction(directoryPath: fixture.directory.path)
            let transactionID = UUID()
            XCTAssertThrowsError(try transaction.execute(proof: fixture.proof,
                transactionID: transactionID, simulateCrashAfter: phase)) { error in
                    XCTAssertEqual(error as? HelperThreeFileUninstallTransaction.TransactionError,
                                   .injectedCrash(phase))
                }
            XCTAssertTrue(try transaction.inspectPendingJournal())
            _ = try transaction.reconcile(expectedTransactionID: transactionID)
            let shouldBeRemoved = phase == .committed
            for name in ["Example.dylib", "Example.plist", "Example.fk.json"] {
                XCTAssertEqual(FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent(name).path),
                               !shouldBeRemoved, "Unexpected file state for \(name) after \(phase)")
            }
            XCTAssertFalse(try transaction.inspectPendingJournal())
        }
    }

    func testLastBoundaryAuthorizationFailureLeavesAllFilesAndNoJournal() throws {
        try requireRoot()
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let transaction = try HelperThreeFileUninstallTransaction(directoryPath: fixture.directory.path)
        enum Expected: Error { case denied }
        XCTAssertThrowsError(try transaction.execute(proof: fixture.proof,
            preMutationAuthorization: { throw Expected.denied }))
        for name in ["Example.dylib", "Example.plist", "Example.fk.json"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent(name).path))
        }
        XCTAssertFalse(try transaction.inspectPendingJournal())
    }

    func testHashMismatchPreventsAnyRemoval() throws {
        try requireRoot()
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        try Data("changed".utf8).write(to: fixture.directory.appendingPathComponent("Example.dylib"))
        let transaction = try HelperThreeFileUninstallTransaction(directoryPath: fixture.directory.path)
        XCTAssertThrowsError(try transaction.execute(proof: fixture.proof))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("Example.plist").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("Example.fk.json").path))
    }
}
