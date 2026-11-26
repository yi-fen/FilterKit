import Foundation
import Dispatch
import Glibc

struct TestIdentityProvider: HelperPeerIdentityProviding {
    let hash: String
    func identity(for credentials: HelperSocketPeerCredentials) throws -> HelperPeerIdentity {
        HelperPeerIdentity(uid: credentials.uid, gid: credentials.gid, pid: credentials.pid,
                           cdHashHex: hash, pidVersion: nil, auditSessionID: nil)
    }
}

@main struct P212Harness {
    static func main() async throws {
        _ = signal(SIGPIPE, SIG_IGN)
        let directory = "/tmp/filterkit-p212-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory)
        let path = directory + "/helper.sock"
        let hash = String(repeating: "a", count: 40)
        let provider = TestIdentityProvider(hash: hash)
        let trust = HelperPeerTrustPolicy(allowedUIDs: [UInt32(getuid())], allowedCDHashes: [hash])
        let server = UnixDomainSocketServer(socketPath: path, socketMode: 0o660, socketGroupID: UInt32(getgid()),
            identityProvider: provider, trustEvaluator: trust) { request, context in
                guard request.messageType == .healthRequest else {
                    return HelperIPCEnvelope(messageType: .rejected, requestID: request.requestID, nonce: context.sessionNonce)
                }
                let status = HelperStatusResponse(helperReachable: true, recoveryStatus: .clean,
                    checkedAt: Date(), protocolVersion: HelperIPCEnvelope.currentVersion)
                let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
                return HelperIPCEnvelope(messageType: .healthResponse, requestID: request.requestID,
                    nonce: context.sessionNonce, payload: try encoder.encode(status))
            }
        DispatchQueue.global().async { try? server.run() }
        for _ in 0..<100 {
            if FileManager.default.fileExists(atPath: path) { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let client = UnixDomainSocketTransport(socketPath: path, identityProvider: provider, trustEvaluator: trust)
        let request = HelperIPCEnvelope(messageType: .healthRequest)
        let response = try await client.exchange(request)
        guard response.messageType == .healthResponse, response.requestID == request.requestID,
              let payload = response.payload else { throw NSError(domain: "P212", code: 1) }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let status = try decoder.decode(HelperStatusResponse.self, from: payload)
        guard status.helperReachable, status.recoveryStatus == .clean else { throw NSError(domain: "P212", code: 2) }
        print("PASS: AF_UNIX nonce-bound authenticated Health round-trip; requestID matched; status=clean")
        let wrongProvider = TestIdentityProvider(hash: String(repeating: "f", count: 40))
        let untrustedClient = UnixDomainSocketTransport(socketPath: path, identityProvider: wrongProvider, trustEvaluator: trust)
        do {
            _ = try await untrustedClient.exchange(HelperIPCEnvelope(messageType: .healthRequest))
            throw NSError(domain: "P212", code: 3, userInfo: [NSLocalizedDescriptionKey: "untrusted CDHash unexpectedly accepted"])
        } catch UnixDomainSocketTransport.SocketError.peerRejected {
            print("PASS: untrusted peer CDHash rejected before request dispatch")
        }
        server.stop()
        // Let the accept loop and per-connection worker release their semaphore captures.
        try await Task.sleep(nanoseconds: 250_000_000)
        try? FileManager.default.removeItem(atPath: directory)
    }
}
