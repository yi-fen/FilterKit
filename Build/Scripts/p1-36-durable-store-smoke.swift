import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

func require136(_ value: @autoclosure () -> Bool, _ message: String) throws {
    guard value() else { throw NSError(domain: "P1-36", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}

@main
struct P136DurableStoreSmoke {
    static func main() throws {
        let directory = NSTemporaryDirectory() + "filterkit-p136-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: directory) }
        try require136(chmod(directory, 0o700) == 0, "could not prepare private journal directory")

        var journal = try HelperInstallerTransactionJournal(action: .install,
            releaseIdentifier: "1.0.0-p136", generation: 11)
        try journal.apply(.verifyArtifacts)
        let store = HelperInstallerDurableJournalStore(directoryPath: directory)
        try store.save(journal)
        let restored = try store.load(transactionID: journal.transactionID)
        try require136(restored == journal, "durable journal round-trip mismatch")
        let recovery = try HelperInstallerRecoveryAssessment.assess(restored)
        try require136(recovery.recommendation == .resumeVerification, "unexpected crash recovery assessment")

        let fileNames = try FileManager.default.contentsOfDirectory(atPath: directory)
        try require136(fileNames == [journal.transactionID.uuidString.lowercased() + ".json"], "unexpected temporary or extra files")

        let unsafeDirectory = directory + "-unsafe"
        try FileManager.default.createDirectory(atPath: unsafeDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: unsafeDirectory) }
        try require136(chmod(unsafeDirectory, 0o755) == 0, "could not prepare unsafe directory")
        do {
            try HelperInstallerDurableJournalStore(directoryPath: unsafeDirectory).save(journal)
            throw NSError(domain: "P1-36", code: 2, userInfo: [NSLocalizedDescriptionKey: "unsafe journal directory accepted"])
        } catch is HelperInstallerDurableJournalStore.StoreError { }

        var encoded = try JSONEncoder().encode(journal)
        var object = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        var entries = object["entries"] as! [[String: Any]]
        entries[0]["hash"] = String(repeating: "f", count: 64)
        object["entries"] = entries
        encoded = try JSONSerialization.data(withJSONObject: object)
        let corrupted = try JSONDecoder().decode(HelperInstallerTransactionJournal.self, from: encoded)
        do {
            _ = try HelperInstallerRecoveryAssessment.assess(corrupted)
            throw NSError(domain: "P1-36", code: 3, userInfo: [NSLocalizedDescriptionKey: "corrupt journal assessed as recoverable"])
        } catch is HelperInstallerTransactionJournal.JournalError { }

        print("PASS: root-owned 0700 journal directory accepted")
        print("PASS: atomic journal save and verified load round-trip")
        print("PASS: temporary file cleaned after commit")
        print("PASS: non-0700 directory rejected")
        print("PASS: recovery assessment validates journal chain before recommendation")
    }
}
