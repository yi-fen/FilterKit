import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

final class P132Audit: HelperAuditSink {
    private(set) var records: [HelperAuditRecord] = []
    func append(_ record: HelperAuditRecord) throws { records.append(record) }
}

func require132(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw NSError(domain: "P1-32", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}

@main
struct P132HelperStatusSmoke {
    static func main() throws {
        let peer = HelperSocketPeerCredentials(uid: 501, gid: 501, pid: 132)
        let identity = HelperPeerIdentity(uid: 501, gid: 501, pid: 132,
            cdHashHex: String(repeating: "a", count: 40), pidVersion: nil, auditSessionID: nil)
        let nonce = String(repeating: "b", count: 32)
        let context = HelperAuthenticatedPeerContext(peer: peer, identity: identity,
            sessionNonce: nonce, authenticatedAt: Date())
        let manifest = HelperDeploymentManifest.disabledTemplate(routeIdentifier: "p1-32",
            jbRootPath: "/var/jb", tweakInjectPath: "/var/jb/usr/lib/TweakInject",
            stagingRootPath: "/var/jb/var/mobile/FilterKit/Staging",
            socketPath: "/var/jb/Library/FilterKit/helper.sock")
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("fk-p132-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        _ = chmod(root.path, 0o700)
        let audit = P132Audit()
        let dispatcher = HelperRequestDispatcher(manifest: manifest, audit: audit, pluginDirectory: root.path)

        let health = HelperIPCEnvelope(messageType: .healthRequest, nonce: nonce)
        let healthResponse = dispatcher.dispatch(health, context: context)
        try require132(healthResponse.messageType == .healthResponse, "health request rejected")
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let status = try decoder.decode(HelperStatusResponse.self, from: healthResponse.payload!)
        try require132(status.helperReachable && status.recoveryStatus == .clean, "wrong structured health status")

        let now = Date()
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let inspectBody = HelperMaintenanceRecoveryRequest(action: .inspect, requestNonce: UUID(), requestedAt: now)
        let inspect = HelperIPCEnvelope(messageType: .maintenanceRecoveryRequest, createdAt: now,
            nonce: nonce, payload: try encoder.encode(inspectBody))
        let inspectResponse = dispatcher.dispatch(inspect, context: context, now: now)
        try require132(inspectResponse.messageType == .maintenanceRecoveryResponse, "maintenance inspect rejected")
        let inspectResult = try decoder.decode(HelperMaintenanceRecoveryResponse.self, from: inspectResponse.payload!)
        try require132(inspectResult.result == .inspected && inspectResult.recoveryStatus == .clean, "maintenance inspect mismatch")

        let recoveryTime = Date()
        let recoveryBody = HelperMaintenanceRecoveryRequest(action: .reconcileThreeFileTransaction,
            requestNonce: UUID(), requestedAt: recoveryTime)
        let recovery = HelperIPCEnvelope(messageType: .maintenanceRecoveryRequest, createdAt: recoveryTime,
            nonce: nonce, payload: try encoder.encode(recoveryBody))
        let recoveryResponse = dispatcher.dispatch(recovery, context: context, now: recoveryTime)
        try require132(recoveryResponse.messageType == .maintenanceRecoveryResponse, "maintenance response missing")
        let recoveryResult = try decoder.decode(HelperMaintenanceRecoveryResponse.self, from: recoveryResponse.payload!)
        try require132(recoveryResult.result == .recoveryNotReleased, "recovery mutation escaped closed gate")
        let remainingFiles = try FileManager.default.contentsOfDirectory(atPath: root.path)
        try require132(remainingFiles.isEmpty, "maintenance request mutated plugin directory")

        let replay = dispatcher.dispatch(recovery, context: context, now: recoveryTime)
        let replayReason = try decoder.decode(HelperRequestDispatcher.Rejection.self, from: replay.payload!)
        try require132(replayReason.code == .replayedRequest, "maintenance replay accepted")
        try require132(audit.records.contains(where: { $0.reasonCode == "maintenance_inspect" }), "inspection not audited")
        // A corrupt transaction journal must remain observable through health IPC while
        // deployment requests are denied with a stable recovery-specific reason.
        let invalidRoot = root.appendingPathComponent("invalid")
        try FileManager.default.createDirectory(at: invalidRoot, withIntermediateDirectories: true)
        _ = chmod(invalidRoot.path, 0o700)
        let journalPath = invalidRoot.appendingPathComponent(".filterkit-three-file.journal")
        _ = FileManager.default.createFile(atPath: journalPath.path, contents: Data("broken".utf8))
        _ = chmod(journalPath.path, 0o600)
        let guardedDispatcher = HelperRequestDispatcher(manifest: manifest, audit: audit,
            pluginDirectory: invalidRoot.path)
        let invalidHealth = guardedDispatcher.dispatch(HelperIPCEnvelope(messageType: .healthRequest, nonce: nonce),
                                                       context: context)
        let invalidStatus = try decoder.decode(HelperStatusResponse.self, from: invalidHealth.payload!)
        try require132(invalidStatus.recoveryStatus == .invalidJournal, "invalid journal not surfaced to App")
        let pluginID = UUID()
        let stamp = Date()
        let dylibOperation = HelperOperationRequest(requestID: UUID(), operation: .installDylib,
            pluginID: pluginID, stagingRelativePath: "task/Demo.dylib", targetFileName: "Demo.dylib",
            expectedSHA256: String(repeating: "c", count: 64), createdAt: stamp)
        let plistOperation = HelperOperationRequest(requestID: UUID(), operation: .replaceFilterPlist,
            pluginID: pluginID, stagingRelativePath: "task/Demo.plist", targetFileName: "Demo.plist",
            expectedSHA256: String(repeating: "d", count: 64), createdAt: stamp)
        let batch = try HelperDeploymentBatchRequest.make(pluginID: pluginID,
            operations: [dylibOperation, plistOperation], createdAt: stamp)
        let batchEnvelope = HelperIPCEnvelope(messageType: .deploymentBatchRequest, requestID: batch.batchID,
            createdAt: stamp, nonce: nonce, payload: try encoder.encode(batch))
        let batchResponse = guardedDispatcher.dispatch(batchEnvelope, context: context, now: stamp)
        let batchRejection = try decoder.decode(HelperRequestDispatcher.Rejection.self, from: batchResponse.payload!)
        try require132(batchRejection.code == .invalidTransactionJournal, "deployment not blocked by invalid journal")

        try require132(!HelperRequestDispatcher.executionReleased && !HelperDeploymentCoordinator.executionReleased,
                       "deployment gate unexpectedly enabled")
        print("P1-32 Helper status smoke: PASS (structured health, clean/invalid recovery status, authenticated maintenance inspect, reconcile fail-closed, deployment blocked by invalid journal, replay guard, audit, no filesystem mutation)")
    }
}
