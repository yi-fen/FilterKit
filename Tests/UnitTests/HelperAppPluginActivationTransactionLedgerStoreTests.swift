import XCTest
@testable import FilterKit

final class HelperAppPluginActivationTransactionLedgerStoreTests: XCTestCase {
    func testLedgerStoreRejectsRelativeDirectory() {
        XCTAssertThrowsError(try HelperAppPluginActivationTransactionLedgerStore(directoryPath: "Library/FilterKit/Helper"))
    }

    func testLedgerStoreRejectsWorldWritableDirectory() throws {
        // /tmp is intentionally world-writable on supported Unix test hosts. The production
        // ledger must refuse it rather than relaxing its root-owned directory requirement.
        let store = try HelperAppPluginActivationTransactionLedgerStore(directoryPath: "/tmp")
        XCTAssertThrowsError(try store.load())
    }

    func testCapacityFailsClosedWithoutEvictingExistingCommand() throws {
        try withStore(maximumRecords: 1) { store in
            let (first, firstPlan, firstTransaction) = makeCommandAndPlan()
            try store.insertExecuting(try HelperAppPluginActivationTransactionRecord(
                command: first, plan: firstPlan, transactionID: firstTransaction))

            let (second, secondPlan, secondTransaction) = makeCommandAndPlan()
            XCTAssertThrowsError(try store.insertExecuting(HelperAppPluginActivationTransactionRecord(
                command: second, plan: secondPlan, transactionID: secondTransaction))) { error in
                XCTAssertEqual(error as? HelperAppPluginActivationTransactionLedgerStore.StoreError, .capacityReached)
            }
            let retained = try store.record(commandRequestID: first.requestID, pluginID: first.pluginID,
                targetBundleIdentifier: first.targetBundleIdentifier)
            XCTAssertEqual(retained?.transactionID, firstTransaction)
        }
    }

    func testUnknownCanOnlyResolveWhenJournalEvidenceHashesMatchLedger() throws {
        try withStore { store in
            let (command, plan, transactionID) = makeCommandAndPlan()
            let row = try HelperAppPluginActivationTransactionRecord(command: command, plan: plan,
                transactionID: transactionID)
            try store.insertExecuting(row)
            _ = try store.transition(commandRequestID: command.requestID, pluginID: command.pluginID,
                targetBundleIdentifier: command.targetBundleIdentifier, to: .outcomeUnknown)

            XCTAssertThrowsError(try store.resolveUnknown(commandRequestID: command.requestID,
                transactionID: transactionID, pluginID: command.pluginID,
                targetBundleIdentifier: command.targetBundleIdentifier,
                disposition: .committed, observedPlistSHA256: String(repeating: "f", count: 64),
                observedManifestSHA256: plan.manifestAfterSHA256))

            let stillUnknown = try XCTUnwrap(store.record(commandRequestID: command.requestID,
                pluginID: command.pluginID, targetBundleIdentifier: command.targetBundleIdentifier))
            XCTAssertEqual(stillUnknown.state, .outcomeUnknown)

            let resolved = try store.resolveUnknown(commandRequestID: command.requestID,
                transactionID: transactionID, pluginID: command.pluginID,
                targetBundleIdentifier: command.targetBundleIdentifier,
                disposition: .committed, observedPlistSHA256: plan.filterAfterSHA256,
                observedManifestSHA256: plan.manifestAfterSHA256)
            XCTAssertEqual(resolved.state, .committed)
        }
    }

    func testUnknownCanResolveToRolledBackOnlyForOriginalHashes() throws {
        try withStore { store in
            let (command, plan, transactionID) = makeCommandAndPlan()
            try store.insertExecuting(try HelperAppPluginActivationTransactionRecord(command: command,
                plan: plan, transactionID: transactionID))
            _ = try store.transition(commandRequestID: command.requestID, pluginID: command.pluginID,
                targetBundleIdentifier: command.targetBundleIdentifier, to: .outcomeUnknown)
            let resolved = try store.resolveUnknown(commandRequestID: command.requestID,
                transactionID: transactionID, pluginID: command.pluginID,
                targetBundleIdentifier: command.targetBundleIdentifier,
                disposition: .rolledBack, observedPlistSHA256: plan.filterBeforeSHA256,
                observedManifestSHA256: plan.manifestBeforeSHA256)
            XCTAssertEqual(resolved.state, .rolledBack)
        }
    }

    private func withStore(maximumRecords: Int = 512,
                           _ body: (HelperAppPluginActivationTransactionLedgerStore) throws -> Void) throws {
        guard geteuid() == 0 else { throw XCTSkip("Root-owned ledger test") }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("fk-activation-ledger-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(HelperAppPluginActivationTransactionLedgerStore(directoryPath: directory.path,
            maximumRecords: maximumRecords))
    }

    private func makeCommandAndPlan() -> (HelperAppPluginActivationCommand, HelperAppPluginActivationPlan, UUID) {
        let requestID = UUID(), pluginID = UUID(), transactionID = UUID()
        let beforeP = String(repeating: "a", count: 64)
        let beforeM = String(repeating: "b", count: 64)
        let afterP = String(repeating: "c", count: 64)
        let afterM = String(repeating: "d", count: 64)
        let command = HelperAppPluginActivationCommand(requestID: requestID, pluginID: pluginID,
            targetBundleIdentifier: "com.example.host", desiredEnabled: true, expectedEnabled: false,
            dylibFileName: "Example.dylib", plistFileName: "Example.plist",
            expectedFilterSHA256: beforeP, expectedManifestSHA256: beforeM,
            snapshotRevision: 1, createdAt: Date())
        let plan = HelperAppPluginActivationPlan(requestID: requestID, pluginID: pluginID,
            targetBundleIdentifier: "com.example.host", previousEnabled: false, desiredEnabled: true,
            filterBeforeSHA256: beforeP, filterAfterSHA256: afterP,
            manifestBeforeSHA256: beforeM, manifestAfterSHA256: afterM, changed: true)
        return (command, plan, transactionID)
    }
}
