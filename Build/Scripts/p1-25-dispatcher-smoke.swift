import Foundation

final class P125MemoryAudit: HelperAuditSink {
    private(set) var records: [HelperAuditRecord] = []
    func append(_ record: HelperAuditRecord) throws { records.append(record) }
}

func require125(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw NSError(domain: "P1-25", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}

@main
struct P125DispatcherSmoke {
    static func main() throws {
        let peer = HelperSocketPeerCredentials(uid: 501, gid: 501, pid: 123)
        let identity = HelperPeerIdentity(uid: 501, gid: 501, pid: 123,
            cdHashHex: String(repeating: "a", count: 40), pidVersion: nil, auditSessionID: nil)
        let nonce = String(repeating: "b", count: 32)
        let context = HelperAuthenticatedPeerContext(peer: peer, identity: identity,
            sessionNonce: nonce, authenticatedAt: Date())
        let manifest = HelperDeploymentManifest.disabledTemplate(routeIdentifier: "smoke",
            jbRootPath: "/var/jb", tweakInjectPath: "/var/jb/usr/lib/TweakInject",
            stagingRootPath: "/var/jb/var/mobile/FilterKit/Staging",
            socketPath: "/var/jb/Library/FilterKit/helper.sock")
        let audit = P125MemoryAudit()
        let dispatcher = HelperRequestDispatcher(manifest: manifest, audit: audit)

        let health = HelperIPCEnvelope(messageType: .healthRequest, nonce: nonce)
        let healthResponse = dispatcher.dispatch(health, context: context)
        try require125(healthResponse.messageType == .healthResponse, "valid health request rejected")

        let wrongNonce = HelperIPCEnvelope(messageType: .healthRequest, nonce: "wrong")
        let wrongResponse = dispatcher.dispatch(wrongNonce, context: context)
        try require125(wrongResponse.messageType == .rejected, "wrong session nonce accepted")

        let operationID = UUID()
        let operation = HelperOperationRequest(requestID: operationID, operation: .installDylib,
            pluginID: UUID(), stagingRelativePath: "task/Demo.dylib", targetFileName: "Demo.dylib",
            expectedSHA256: String(repeating: "c", count: 64), createdAt: Date())
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let timestamp = Date()
        let operationEnvelope = HelperIPCEnvelope(messageType: .operationRequest, requestID: operationID,
            createdAt: timestamp, nonce: nonce, payload: try encoder.encode(operation))
        let denied = dispatcher.dispatch(operationEnvelope, context: context, now: timestamp)
        try require125(denied.messageType == .rejected, "operation escaped release gate")
        let denial = try JSONDecoder().decode(HelperRequestDispatcher.Rejection.self, from: denied.payload!)
        try require125(denial.code == .executionDisabled, "wrong release-gate reason")

        let replay = dispatcher.dispatch(operationEnvelope, context: context, now: timestamp)
        let replayDenial = try JSONDecoder().decode(HelperRequestDispatcher.Rejection.self, from: replay.payload!)
        try require125(replayDenial.code == .replayedRequest, "replayed request not rejected")

        let malformed = HelperIPCEnvelope(messageType: .operationRequest, nonce: nonce, payload: Data("{}".utf8))
        let malformedResponse = dispatcher.dispatch(malformed, context: context)
        let malformedDenial = try JSONDecoder().decode(HelperRequestDispatcher.Rejection.self, from: malformedResponse.payload!)
        try require125(malformedDenial.code == .malformedOperation, "malformed operation not rejected")
        try require125(audit.records.contains(where: { $0.reasonCode == "execution_disabled" }), "release-gate denial not audited")
        try require125(!HelperRequestDispatcher.executionReleased && !HelperDeploymentCoordinator.executionReleased,
                       "global execution release gate changed")
        print("P1-25 dispatcher smoke: PASS (session binding, health, malformed request, replay denial, audited operation denial, release gates closed)")
    }
}
