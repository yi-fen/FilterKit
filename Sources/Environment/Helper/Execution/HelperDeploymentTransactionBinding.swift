import Foundation

/// Immutable cross-journal identity. Every field is derived inside the Helper from the
/// validated batch and authorized payloads; IPC callers cannot supply this as authority.
struct HelperDeploymentTransactionBinding: Codable, Equatable {
    let batchID: UUID
    let batchDigest: String
    let transactionID: UUID
    let requestIDs: [UUID]
    let pluginID: UUID
    let dylibSHA256: String
    let plistSHA256: String
    let manifestSHA256: String

    func validate() -> Bool {
        HelperPolicy.isValidHash(batchDigest) &&
        [dylibSHA256, plistSHA256, manifestSHA256].allSatisfy(HelperPolicy.isValidHash) &&
        !requestIDs.isEmpty && Set(requestIDs).count == requestIDs.count &&
        transactionID != UUID(uuidString: "00000000-0000-0000-0000-000000000000")
    }
}

/// Read-only reconciliation verdict. Any missing or mismatched side is a hard stop;
/// this policy never authorizes filesystem mutation.
enum HelperDeploymentJournalReconciliation {
    enum Verdict: Equatable { case matched, artifactsConsistentPending, ledgerMissing, transactionMissing, identityMismatch, artifactMismatch }
    static func compare(ledger: HelperDeploymentDurableLedgerStore.Record?,
                        transaction: HelperDeploymentTransactionBinding?,
                        actualHashes: (dylib: String?, plist: String?, manifest: String?),
                        previousHashes: (dylib: String?, plist: String?, manifest: String?),
                        committed: Bool = false) -> Verdict {
        guard let ledger else { return .ledgerMissing }
        guard let transaction else { return .transactionMissing }
        guard ledger.batchID == transaction.batchID,
              ledger.digest.caseInsensitiveCompare(transaction.batchDigest) == .orderedSame,
              ledger.transactionID == transaction.transactionID,
              Set(ledger.requestIDs) == Set(transaction.requestIDs) else { return .identityMismatch }
        let actual = [actualHashes.dylib, actualHashes.plist, actualHashes.manifest]
        let expected = [transaction.dylibSHA256, transaction.plistSHA256, transaction.manifestSHA256]
        let previous = [previousHashes.dylib, previousHashes.plist, previousHashes.manifest]
        let isNew = zip(actual, expected).allSatisfy { value, hash in value?.caseInsensitiveCompare(hash) == .orderedSame }
        if isNew { return .matched }
        if committed { return .artifactMismatch }
        let isKnownTransactionState = zip(actual, zip(previous, expected)).allSatisfy { value, hashes in
            guard let value else { return true } // absence is valid only after startup verifies the matching backup evidence
            return value.caseInsensitiveCompare(hashes.1) == .orderedSame ||
                hashes.0.map { value.caseInsensitiveCompare($0) == .orderedSame } == true
        }
        return isKnownTransactionState ? .artifactsConsistentPending : .artifactMismatch
    }
}
