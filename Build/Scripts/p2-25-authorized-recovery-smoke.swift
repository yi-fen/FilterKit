import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

private final class P225MemoryAuditSink: HelperAuditSink {
    private(set) var records: [HelperAuditRecord] = []
    func append(_ record: HelperAuditRecord) throws { records.append(record) }
}

@main
struct P225AuthorizedRecoverySmoke {
    static func main() throws {
        precondition(geteuid() == 0, "run as root to exercise root-owned transaction stores")
        let base = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("filterkit-p225-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: base) }

        try runScenario(base: base, crashPhase: .installingDylib, expected: .rolledBack, expectedLedger: .rolledBack)
        try runScenario(base: base, crashPhase: .committed, expected: .committed, expectedLedger: .completed)
        print("PASS: explicit operator confirmation and unprivileged App/kernel identity authorization")
        print("PASS: transaction-ID-scoped recovery rejects unrelated journal identity")
        print("PASS: interrupted pre-commit transaction rolls back and finalizes ledger as rolledBack")
        print("PASS: committed transaction cleanup finalizes ledger as completed")
        print("PASS: ledger finalization is idempotent and preserves immutable binding")
    }

    static func runScenario(base: URL, crashPhase: HelperThreeFileTransactionExecutor.Phase,
                            expected: HelperThreeFileTransactionExecutor.RecoveryDisposition,
                            expectedLedger: HelperDeploymentDurableLedgerStore.Record.State) throws {
        let pluginDirectory = base.appendingPathComponent("plugins-\(UUID().uuidString)", isDirectory: true)
        let ledgerDirectory = base.appendingPathComponent("ledger-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: pluginDirectory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o755])
        try FileManager.default.createDirectory(at: ledgerDirectory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])

        let pluginID = UUID(), batchID = UUID(), transactionID = UUID()
        let requestIDs = [UUID(), UUID()]
        let dylibName = "P225Fixture.dylib", plistName = "P225Fixture.plist"
        let dylib = Data("fixture-dylib-\(UUID().uuidString)".utf8)
        let plist = try PropertyListSerialization.data(fromPropertyList: ["Filter": ["Bundles": ["com.example.p225"]]],
            format: .xml, options: 0)
        let dylibHash = SHA256Digest.hex(dylib), plistHash = SHA256Digest.hex(plist)
        let manifestObject: [String: Any] = [
            "schemaVersion": 3, "pluginID": pluginID.uuidString,
            "dylibFileName": dylibName, "plistFileName": plistName,
            "dylibSHA256": dylibHash, "plistSHA256": plistHash,
            "hardBoundBundleIdentifier": "com.example.p225",
            "softAssociatedBundleIdentifiers": [String](),
            "machOIdentitySHA256": String(repeating: "a", count: 64)
        ]
        let manifest = try JSONSerialization.data(withJSONObject: manifestObject, options: [.sortedKeys])
        let binding = HelperDeploymentTransactionBinding(batchID: batchID,
            batchDigest: String(repeating: "b", count: 64), transactionID: transactionID,
            requestIDs: requestIDs, pluginID: pluginID, dylibSHA256: dylibHash,
            plistSHA256: plistHash, manifestSHA256: SHA256Digest.hex(manifest))
        precondition(binding.validate())

        let store = try HelperDeploymentDurableLedgerStore(directoryPath: ledgerDirectory.path)
        let ledger = HelperDeploymentIdempotencyLedger(durableStore: store)
        precondition(ledger.begin(batchID: batchID, digest: binding.batchDigest,
            requestIDs: requestIDs, transactionID: transactionID) == .accepted)

        let executor = try HelperThreeFileTransactionExecutor(directoryPath: pluginDirectory.path)
        do {
            _ = try executor.execute(pluginID: pluginID, dylibName: dylibName, plistName: plistName,
                dylib: dylib, plist: plist, manifest: manifest, route: .firstInstall,
                simulateCrashAfter: crashPhase, transactionID: transactionID, deploymentBinding: binding)
            throw NSError(domain: "P2-25", code: 1, userInfo: [NSLocalizedDescriptionKey: "crash injection did not fire"])
        } catch HelperThreeFileTransactionExecutor.TransactionError.injectedCrash(crashPhase) { }

        let evidence = try executor.inspectPendingEvidence()
        guard let evidence, evidence.transactionID == transactionID else {
            throw NSError(domain: "P2-25", code: 2, userInfo: [NSLocalizedDescriptionKey: "pending transaction evidence missing"])
        }
        let pid = Int32(getpid())
        // Simulate the real App (mobile/unprivileged) peer while the smoke process itself
        // runs as root to exercise root-owned stores and the privileged Helper coordinator.
        let identity = HelperPeerIdentity(uid: 501, gid: 501, pid: pid,
            cdHashHex: String(repeating: "c", count: 40), pidVersion: 1,
            auditSessionID: 1, auditTokenDigest: String(repeating: "d", count: 64))
        let context = HelperAuthenticatedPeerContext(peer: HelperSocketPeerCredentials(uid: 501, gid: 501, pid: pid),
            identity: identity, sessionNonce: String(repeating: "e", count: 32), authenticatedAt: Date())
        do {
            _ = try HelperRecoveryAuthorization.authorize(context: context, transactionID: transactionID,
                requestNonce: UUID(), operatorConfirmed: false)
            throw NSError(domain: "P2-25", code: 3, userInfo: [NSLocalizedDescriptionKey: "unconfirmed recovery was authorized"])
        } catch HelperRecoveryAuthorization.AuthorizationError.confirmationRequired { }
        let wrongAuthorization = try HelperRecoveryAuthorization.authorize(context: context,
            transactionID: UUID(), requestNonce: UUID(), operatorConfirmed: true)
        do {
            _ = try HelperAuthorizedRecoveryCoordinator(audit: P225MemoryAuditSink()).reconcileThreeFileTransaction(
                pluginDirectory: pluginDirectory.path, ledgerStore: store, authorization: wrongAuthorization)
            throw NSError(domain: "P2-25", code: 5, userInfo: [NSLocalizedDescriptionKey: "wrong transaction authorization was accepted"])
        } catch HelperAuthorizedRecoveryCoordinator.RecoveryError.invalidJournal { }

        let authorization = try HelperRecoveryAuthorization.authorize(context: context,
            transactionID: transactionID, requestNonce: UUID(), operatorConfirmed: true)

        // Simulate a process crash after filesystem reconciliation and durable ledger
        // finalization but before journal removal. The retained journal must permit a retry.
        if expected == .committed {
            let firstPass = try executor.reconcile(expectedTransactionID: transactionID, preserveJournal: true)
            precondition(firstPass == .committed)
            try store.finalizeRecovered(binding: binding, disposition: .committed)
            let retainedEvidence = try executor.inspectPendingEvidence()
            precondition(retainedEvidence != nil)
        }

        let audit = P225MemoryAuditSink()
        let result = try HelperAuthorizedRecoveryCoordinator(audit: audit).reconcileThreeFileTransaction(
            pluginDirectory: pluginDirectory.path, ledgerStore: store, authorization: authorization)
        precondition(audit.records.first?.reasonCode == "transaction_recovery_started")
        precondition(audit.records.last?.outcome == .succeeded)
        precondition(result == (expected == .committed ? .committed : .rolledBack))
        let records = try store.load()
        guard let recovered = records.first(where: { $0.batchID == batchID }) else {
            throw NSError(domain: "P2-25", code: 4, userInfo: [NSLocalizedDescriptionKey: "ledger record missing after recovery"])
        }
        precondition(recovered.state == expectedLedger)
        try store.finalizeRecovered(binding: binding,
            disposition: expectedLedger == .completed ? .committed : .rolledBack)
        let finalizedRecords = try store.load()
        precondition(finalizedRecords.first(where: { $0.batchID == batchID })?.state == expectedLedger)
        precondition(HelperStartupRecoveryCheck().inspectDetailed(pluginDirectory: pluginDirectory.path,
            deploymentLedgerStore: store) == .clean)
    }
}
