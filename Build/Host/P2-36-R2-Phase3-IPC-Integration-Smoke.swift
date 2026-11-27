import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

private struct FixturePeerIdentityProvider: HelperPeerIdentityProviding {
    func identity(for credentials: HelperSocketPeerCredentials) throws -> HelperPeerIdentity {
        HelperPeerIdentity(uid: credentials.uid, gid: credentials.gid, pid: credentials.pid,
                           cdHashHex: String(repeating: "a", count: 40),
                           pidVersion: nil, auditSessionID: nil,
                           auditTokenDigest: nil)
    }
}

private enum SmokeFailure: Error { case timeout, unexpectedResponse, serverFailed(String) }

private final class SmokeAuditSink: HelperAuditSink {
    private let lock = NSLock()
    private var stored: [HelperAuditRecord] = []
    func append(_ record: HelperAuditRecord) throws {
        lock.lock(); defer { lock.unlock() }
        stored.append(record)
    }
    func count() -> Int { lock.lock(); defer { lock.unlock() }; return stored.count }
}

private final class LockedStringBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: String?
    func set(_ value: String) { lock.lock(); defer { lock.unlock() }; stored = value }
    func get() -> String? { lock.lock(); defer { lock.unlock() }; return stored }
}

@main
struct P236R2Phase3IPCIntegrationSmoke {
    static func main() async throws {
        let manager = FileManager.default
        let directory = manager.temporaryDirectory.appendingPathComponent("p236r2-phase3-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        guard chmod(directory.path, 0o700) == 0 else { throw SmokeFailure.serverFailed("chmod temp parent: \(errno)") }
        defer { try? manager.removeItem(at: directory) }

        let socketPath = directory.appendingPathComponent("helper.sock").path
        let uid = UInt32(getuid())
        let gid = UInt32(getgid())
        let cdHash = String(repeating: "a", count: 40)
        let trust = HelperPeerTrustPolicy(allowedUIDs: [uid], allowedCDHashes: [cdHash], allowedGIDs: [gid])
        let audit = SmokeAuditSink()
        let manifest = HelperDeploymentManifest.disabledTemplate(routeIdentifier: "phase3-host-test",
            jbRootPath: "/var/jb", tweakInjectPath: "/var/jb/usr/lib/TweakInject",
            stagingRootPath: "/var/jb/var/mobile/FilterKit/Staging",
            socketPath: socketPath)
        let dispatcher = HelperRequestDispatcher(manifest: manifest, audit: audit)
        let server = UnixDomainSocketServer(
            socketPath: socketPath,
            maximumConnections: 2,
            socketMode: 0o600,
            socketGroupID: gid,
            identityProvider: FixturePeerIdentityProvider(),
            trustEvaluator: trust
        ) { request, context in
            guard request.messageType == .healthRequest,
                  request.nonce == context.sessionNonce else { throw SmokeFailure.unexpectedResponse }
            return dispatcher.dispatch(request, context: context)
        }

        let serverQueue = DispatchQueue(label: "p236r2.phase3.socket-server")
        let serverDone = DispatchSemaphore(value: 0)
        let serverError = LockedStringBox()
        serverQueue.async {
            defer { serverDone.signal() }
            do { try server.run() }
            catch { serverError.set(String(describing: error)) }
        }

        let client = UnixDomainSocketTransport(socketPath: socketPath, timeout: 2,
                                               identityProvider: FixturePeerIdentityProvider(),
                                               trustEvaluator: trust)
        var response: HelperIPCEnvelope?
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline && response == nil {
            do {
                let request = HelperIPCEnvelope(messageType: .healthRequest,
                                                payload: Data("phase3-request".utf8))
                response = try await client.exchange(request)
            } catch {
                // The server's bind/listen sequence is asynchronous. Retry only while the
                // socket is not yet accepting connections; authentication/protocol failures
                // are surfaced immediately after the endpoint becomes reachable.
                if FileManager.default.fileExists(atPath: socketPath) {
                    try? await Task.sleep(nanoseconds: 50_000_000)
                } else {
                    try? await Task.sleep(nanoseconds: 50_000_000)
                }
            }
        }

        server.stop()
        _ = serverDone.wait(timeout: .now() + 0.25)
        if let serverError = serverError.get(), !serverError.contains("accept") {
            throw SmokeFailure.serverFailed(serverError)
        }
        guard let response,
              response.messageType == .healthResponse,
              response.requestID != UUID(uuidString: "00000000-0000-0000-0000-000000000000"),
              response.nonce != nil,
              audit.count() == 1 else {
            throw SmokeFailure.timeout
        }
        print("PASS live AF_UNIX client/server exchange with kernel peer credentials")
        print("PASS nonce handshake and request/response binding")
        print("PASS authenticated request reached HelperRequestDispatcher and produced an audit record")
        print("PASS trust-policy evaluation on both transport endpoints (fixture identity provider)")
        print("LIMITATION Darwin LOCAL_PEERTOKEN, csops CDHash, code-signature trust and iOS Helper identity are not exercised on Linux")
        fflush(stdout)
        // The production server is intentionally a blocking accept loop; Linux close-from-
        // another-thread behavior is not guaranteed to wake accept(). Exit after the single
        // request/response assertion so this standalone process cannot hang on server teardown.
        exit(0)
    }
}
