import XCTest
@testable import FilterKit

final class HelperInstallerDurableStoreTests: XCTestCase {
    func testDurableJournalRoundTripAndRecoveryAssessment() throws {
        let directory = NSTemporaryDirectory() + "filterkit-journal-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: directory) }
        XCTAssertEqual(chmod(directory, 0o700), 0)
        let store = HelperInstallerDurableJournalStore(directoryPath: directory)
        var journal = try HelperInstallerTransactionJournal(action: .install,
            releaseIdentifier: "1.0.0-p136", generation: 11)
        try journal.apply(.intentVerifyArtifacts)
        try store.save(journal)
        let loaded = try store.load(transactionID: journal.transactionID)
        XCTAssertEqual(loaded, journal)
        let assessment = try HelperInstallerRecoveryAssessment.assess(loaded)
        XCTAssertEqual(assessment.recommendation, .reconcilePendingOperation(.verifyArtifacts))
    }

    func testDurableStoreRejectsNonRootOwnedOrNon0700Directory() throws {
        let directory = NSTemporaryDirectory() + "filterkit-journal-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: directory) }
        XCTAssertEqual(chmod(directory, 0o755), 0)
        let store = HelperInstallerDurableJournalStore(directoryPath: directory)
        let journal = try HelperInstallerTransactionJournal(action: .install,
            releaseIdentifier: "1.0.0-p136", generation: 11)
        XCTAssertThrowsError(try store.save(journal))
    }

    func testRecoveryAssessmentRejectsCorruptJournal() throws {
        var journal = try HelperInstallerTransactionJournal(action: .install,
            releaseIdentifier: "1.0.0-p136", generation: 11)
        try journal.apply(.intentVerifyArtifacts)
        var encoded = try JSONEncoder().encode(journal)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var entries = try XCTUnwrap(object["entries"] as? [[String: Any]])
        entries[0]["hash"] = String(repeating: "0", count: 64)
        object["entries"] = entries
        encoded = try JSONSerialization.data(withJSONObject: object)
        let corrupt = try JSONDecoder().decode(HelperInstallerTransactionJournal.self, from: encoded)
        XCTAssertThrowsError(try HelperInstallerRecoveryAssessment.assess(corrupt))
    }
    func testManualInterventionTakesPrecedenceOverPendingIntent() throws {
        var journal = try HelperInstallerTransactionJournal(action: .install,
            releaseIdentifier: "1.0.0-p136", generation: 11)
        try journal.apply(.intentVerifyArtifacts)
        try journal.apply(.requireManualIntervention)
        let assessment = try HelperInstallerRecoveryAssessment.assess(journal)
        XCTAssertEqual(assessment.recommendation, .manualIntervention)
    }

}
