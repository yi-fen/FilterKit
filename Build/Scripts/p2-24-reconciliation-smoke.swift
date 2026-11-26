import Foundation

@main
struct P224ReconciliationSmoke {
    static func main() throws {
        let batchID = UUID(), txID = UUID(), pluginID = UUID()
        let requests = [UUID(), UUID()]
        let binding = HelperDeploymentTransactionBinding(batchID: batchID,
            batchDigest: String(repeating: "a", count: 64), transactionID: txID,
            requestIDs: requests, pluginID: pluginID,
            dylibSHA256: String(repeating: "b", count: 64),
            plistSHA256: String(repeating: "c", count: 64),
            manifestSHA256: String(repeating: "d", count: 64))
        precondition(binding.validate())
        let record = HelperDeploymentDurableLedgerStore.Record(batchID: batchID,
            digest: binding.batchDigest, requestIDs: requests, transactionID: txID,
            state: .inProgress, updatedAt: Date())
        let committed = HelperDeploymentJournalReconciliation.compare(ledger: record, transaction: binding,
            actualHashes: (binding.dylibSHA256, binding.plistSHA256, binding.manifestSHA256),
            previousHashes: (nil, nil, nil))
        precondition(committed == .matched)
        let old = (String(repeating: "1", count: 64), String(repeating: "2", count: 64), String(repeating: "3", count: 64))
        let partial = HelperDeploymentJournalReconciliation.compare(ledger: record, transaction: binding,
            actualHashes: (old.0, binding.plistSHA256, nil), previousHashes: old)
        precondition(partial == .artifactsConsistentPending)
        let foreign = HelperDeploymentJournalReconciliation.compare(ledger: record, transaction: binding,
            actualHashes: (String(repeating: "f", count: 64), binding.plistSHA256, nil), previousHashes: old)
        precondition(foreign == .artifactMismatch)
        let encoded = try JSONEncoder().encode(binding)
        let decoded = try JSONDecoder().decode(HelperDeploymentTransactionBinding.self, from: encoded)
        precondition(decoded == binding)

        let ledgerDirectory = NSTemporaryDirectory() + "filterkit-p224-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: ledgerDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: ledgerDirectory) }
        precondition(chmod(ledgerDirectory, 0o700) == 0)
        let store = try HelperDeploymentDurableLedgerStore(directoryPath: ledgerDirectory)
        let ledger = HelperDeploymentIdempotencyLedger(durableStore: store)
        precondition(ledger.begin(batchID: batchID, digest: binding.batchDigest,
            requestIDs: requests, transactionID: txID) == .accepted)
        let restoredLedger = HelperDeploymentIdempotencyLedger(durableStore: store)
        precondition(restoredLedger.begin(batchID: batchID, digest: binding.batchDigest,
            requestIDs: requests, transactionID: UUID()) == .existing(.indeterminate))
        let restoredRecords = try store.load()
        precondition(restoredRecords.first?.transactionID == txID)
        print("PASS: Batch/Transaction identity binding")
        print("PASS: committed three-artifact hash reconciliation")
        print("PASS: partial transaction old/new/absent hash recognition")
        print("PASS: foreign artifact hash rejected")
        print("PASS: binding Codable round-trip")
        print("PASS: durable ledger restart preserves Transaction ID and blocks replay")
    }
}
