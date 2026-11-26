import Foundation

private final class P226MemoryAudit: HelperAuditSink {
    private(set) var records: [HelperAuditRecord] = []
    func append(_ record: HelperAuditRecord) throws { records.append(record) }
}

@main
struct P226MaintenanceIPCSmoke {
    static func main() throws {
        let pid = Int32(getpid())
        let peer = HelperSocketPeerCredentials(uid: 501, gid: 501, pid: pid)
        let identity = HelperPeerIdentity(uid: 501, gid: 501, pid: pid,
            cdHashHex: String(repeating: "a", count: 40), pidVersion: 17,
            auditSessionID: 2, auditTokenDigest: String(repeating: "b", count: 64))
        let context = HelperAuthenticatedPeerContext(peer: peer, identity: identity,
            sessionNonce: String(repeating: "c", count: 32), authenticatedAt: Date())
        let manifest = HelperDeploymentManifest.disabledTemplate(routeIdentifier: "p226-smoke",
            jbRootPath: "/var/jb", tweakInjectPath: "/var/jb/usr/lib/TweakInject",
            stagingRootPath: "/var/jb/var/mobile/FilterKit/Staging",
            socketPath: "/var/jb/Library/FilterKit/helper.sock")
        let audit = P226MemoryAudit()
        let dispatcher = HelperRequestDispatcher(manifest: manifest, audit: audit)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let now = Date()

        let inspectID = UUID()
        let inspect = HelperMaintenanceRecoveryRequest(action: .inspect,
            requestNonce: inspectID, requestedAt: now)
        let inspectEnvelope = HelperIPCEnvelope(messageType: .maintenanceRecoveryRequest,
            requestID: inspectID, createdAt: now, nonce: context.sessionNonce,
            payload: try encoder.encode(inspect))
        let inspectResponse = dispatcher.dispatch(inspectEnvelope, context: context, now: now)
        precondition(inspectResponse.messageType == .maintenanceRecoveryResponse)
        let inspectResult = try decoder.decode(HelperMaintenanceRecoveryResponse.self,
            from: inspectResponse.payload!)
        precondition(inspectResult.result == .inspected)

        let transactionID = UUID()
        let recoveryID = UUID()
        let recovery = HelperMaintenanceRecoveryRequest(action: .reconcileThreeFileTransaction,
            requestNonce: recoveryID, requestedAt: now, transactionID: transactionID,
            operatorConfirmed: true)
        let recoveryEnvelope = HelperIPCEnvelope(messageType: .maintenanceRecoveryRequest,
            requestID: recoveryID, createdAt: now, nonce: context.sessionNonce,
            payload: try encoder.encode(recovery))
        let recoveryResponse = dispatcher.dispatch(recoveryEnvelope, context: context, now: now)
        precondition(recoveryResponse.messageType == .maintenanceRecoveryResponse)
        let result = try decoder.decode(HelperMaintenanceRecoveryResponse.self,
            from: recoveryResponse.payload!)
        precondition(result.result == .recoveryNotReleased)
        precondition(result.transactionID == transactionID)

        let unconfirmedID = UUID()
        let unconfirmed = HelperMaintenanceRecoveryRequest(action: .reconcileThreeFileTransaction,
            requestNonce: unconfirmedID, requestedAt: now, transactionID: UUID(),
            operatorConfirmed: false)
        let unconfirmedEnvelope = HelperIPCEnvelope(messageType: .maintenanceRecoveryRequest,
            requestID: unconfirmedID, createdAt: now, nonce: context.sessionNonce,
            payload: try encoder.encode(unconfirmed))
        precondition(dispatcher.dispatch(unconfirmedEnvelope, context: context, now: now).messageType == .rejected)

        let mismatchID = UUID()
        let mismatch = HelperMaintenanceRecoveryRequest(action: .reconcileThreeFileTransaction,
            requestNonce: UUID(), requestedAt: now, transactionID: UUID(), operatorConfirmed: true)
        let mismatchEnvelope = HelperIPCEnvelope(messageType: .maintenanceRecoveryRequest,
            requestID: mismatchID, createdAt: now, nonce: context.sessionNonce,
            payload: try encoder.encode(mismatch))
        precondition(dispatcher.dispatch(mismatchEnvelope, context: context, now: now).messageType == .rejected)

        precondition(!HelperRequestDispatcher.executionReleased)
        precondition(!HelperRequestDispatcher.pluginAssociationCommitReleased)
        print("PASS: unprivileged App peer maintenance inspection")
        print("PASS: explicit confirmation + transaction-bound authorization over IPC")
        print("PASS: missing confirmation and nonce/requestID mismatch rejected")
        print("PASS: recovery mutation remains unreleased")
    }
}
