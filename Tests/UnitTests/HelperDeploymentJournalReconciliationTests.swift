import XCTest
@testable import FilterKit

final class HelperDeploymentJournalReconciliationTests: XCTestCase {
    private func makeBinding() -> HelperDeploymentTransactionBinding {
        HelperDeploymentTransactionBinding(batchID: UUID(), batchDigest: String(repeating: "a", count: 64),
            transactionID: UUID(), requestIDs: [UUID(), UUID()], pluginID: UUID(),
            dylibSHA256: String(repeating: "b", count: 64), plistSHA256: String(repeating: "c", count: 64),
            manifestSHA256: String(repeating: "d", count: 64))
    }

    func testBindingRejectsMalformedHashesAndDuplicateRequests() {
        var binding = makeBinding()
        XCTAssertTrue(binding.validate())
        binding = HelperDeploymentTransactionBinding(batchID: binding.batchID, batchDigest: "bad",
            transactionID: binding.transactionID, requestIDs: binding.requestIDs, pluginID: binding.pluginID,
            dylibSHA256: binding.dylibSHA256, plistSHA256: binding.plistSHA256, manifestSHA256: binding.manifestSHA256)
        XCTAssertFalse(binding.validate())
    }

    func testLedgerAndTransactionIdentityMustMatch() {
        let b = makeBinding()
        let record = HelperDeploymentDurableLedgerStore.Record(batchID: b.batchID, digest: b.batchDigest,
            requestIDs: b.requestIDs, transactionID: b.transactionID, state: .inProgress, updatedAt: Date())
        XCTAssertEqual(HelperDeploymentJournalReconciliation.compare(ledger: record, transaction: b,
            actualHashes: (b.dylibSHA256, b.plistSHA256, b.manifestSHA256), previousHashes: (nil, nil, nil)), .matched)
        let wrong = HelperDeploymentDurableLedgerStore.Record(batchID: UUID(), digest: b.batchDigest,
            requestIDs: b.requestIDs, transactionID: b.transactionID, state: .inProgress, updatedAt: Date())
        XCTAssertEqual(HelperDeploymentJournalReconciliation.compare(ledger: wrong, transaction: b,
            actualHashes: (b.dylibSHA256, b.plistSHA256, b.manifestSHA256), previousHashes: (nil, nil, nil)), .identityMismatch)
    }

    func testArtifactHashesMustMatchAllThreeFiles() {
        let b = makeBinding()
        let record = HelperDeploymentDurableLedgerStore.Record(batchID: b.batchID, digest: b.batchDigest,
            requestIDs: b.requestIDs, transactionID: b.transactionID, state: .completed, updatedAt: Date())
        XCTAssertEqual(HelperDeploymentJournalReconciliation.compare(ledger: record, transaction: b,
            actualHashes: (b.dylibSHA256, b.plistSHA256, String(repeating: "e", count: 64)), previousHashes: (nil, nil, nil)), .artifactMismatch)
    }
    func testPartialTransactionAcceptsOnlyOldNewOrAbsentHashes() {
        let b = makeBinding()
        let record = HelperDeploymentDurableLedgerStore.Record(batchID: b.batchID, digest: b.batchDigest,
            requestIDs: b.requestIDs, transactionID: b.transactionID, state: .inProgress, updatedAt: Date())
        let old = (String(repeating: "1", count: 64), String(repeating: "2", count: 64), String(repeating: "3", count: 64))
        XCTAssertEqual(HelperDeploymentJournalReconciliation.compare(ledger: record, transaction: b,
            actualHashes: (old.0, b.plistSHA256, nil), previousHashes: old), .artifactsConsistentPending)
        XCTAssertEqual(HelperDeploymentJournalReconciliation.compare(ledger: record, transaction: b,
            actualHashes: (String(repeating: "f", count: 64), b.plistSHA256, nil), previousHashes: old), .artifactMismatch)
    }

}
