import XCTest
@testable import FilterKit

final class HelperAppPluginActivationTransactionLedgerTests: XCTestCase {
    private let hashA = String(repeating: "a", count: 64)
    private let hashB = String(repeating: "b", count: 64)

    private func fixtures() throws -> (HelperAppPluginActivationCommand, HelperAppPluginActivationPlan) {
        let command = HelperAppPluginActivationCommand(
            requestID: UUID(), pluginID: UUID(), targetBundleIdentifier: "com.example.Target",
            desiredEnabled: true, expectedEnabled: false, dylibFileName: "Sample.dylib",
            plistFileName: "Sample.plist", expectedFilterSHA256: hashA,
            expectedManifestSHA256: hashA, snapshotRevision: 1, createdAt: Date())
        let plan = HelperAppPluginActivationPlan(requestID: command.requestID,
            pluginID: command.pluginID, targetBundleIdentifier: command.targetBundleIdentifier,
            previousEnabled: false, desiredEnabled: true, filterBeforeSHA256: hashA,
            filterAfterSHA256: hashB, manifestBeforeSHA256: hashA,
            manifestAfterSHA256: hashB, changed: true)
        return (command, plan)
    }

    func testExecutingCanBecomeCommittedAndRoundTripCodable() throws {
        let (command, plan) = try fixtures()
        var record = try HelperAppPluginActivationTransactionRecord(
            command: command, plan: plan, transactionID: UUID())
        try record.validate()
        try record.transition(to: .committed, now: record.updatedAt.addingTimeInterval(1))
        try record.validate()
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(HelperAppPluginActivationTransactionRecord.self, from: data)
        XCTAssertEqual(decoded, record)
        XCTAssertEqual(decoded.state, .committed)
    }

    func testUnknownCanResolveButTerminalStateCannotChange() throws {
        let (command, plan) = try fixtures()
        var record = try HelperAppPluginActivationTransactionRecord(
            command: command, plan: plan, transactionID: UUID())
        let t1 = record.updatedAt.addingTimeInterval(1)
        try record.transition(to: .outcomeUnknown, now: t1)
        try record.transition(to: .rolledBack, now: t1.addingTimeInterval(1))
        XCTAssertThrowsError(try record.transition(to: .committed, now: t1.addingTimeInterval(2)))
    }

    func testQueryStatusBindsOriginalCommandAndCanonicalBundleID() throws {
        let (command, plan) = try fixtures()
        let tx = UUID()
        let record = try HelperAppPluginActivationTransactionRecord(command: command, plan: plan, transactionID: tx)
        let query = HelperAppPluginActivationTransactionQuery(requestID: UUID(),
            commandRequestID: command.requestID, pluginID: command.pluginID,
            targetBundleIdentifier: command.targetBundleIdentifier.uppercased(), createdAt: Date())
        XCTAssertTrue(query.validate())
        let status = HelperAppPluginActivationTransactionStatus(queryRequestID: query.requestID,
            commandRequestID: record.commandRequestID, pluginID: record.pluginID,
            targetBundleIdentifier: record.targetBundleIdentifier, state: record.state,
            transactionID: record.transactionID, filterSHA256: nil, manifestSHA256: nil, checkedAt: Date())
        XCTAssertTrue(status.matches(query))
    }

    func testQueryRejectsMismatchedPluginIdentity() throws {
        let (command, _) = try fixtures()
        let query = HelperAppPluginActivationTransactionQuery(requestID: UUID(),
            commandRequestID: command.requestID, pluginID: UUID(),
            targetBundleIdentifier: command.targetBundleIdentifier, createdAt: Date())
        let status = HelperAppPluginActivationTransactionStatus(queryRequestID: query.requestID,
            commandRequestID: command.requestID, pluginID: command.pluginID,
            targetBundleIdentifier: command.targetBundleIdentifier, state: nil,
            transactionID: nil, filterSHA256: nil, manifestSHA256: nil, checkedAt: Date())
        XCTAssertFalse(status.matches(query))
    }
}
