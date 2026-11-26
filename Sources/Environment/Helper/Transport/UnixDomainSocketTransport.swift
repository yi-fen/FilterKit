import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// POSIX AF_UNIX stream transport. Each exchange uses a fresh connection and fresh nonce.
/// It refuses to operate unless a platform peer-identity provider and trust policy are supplied.
final class UnixDomainSocketTransport: HelperIPCTransport {
    enum SocketError: Swift.Error, Equatable {
        case unsupportedPlatform, invalidSocketPath, createFailed(Int32), connectFailed(Int32)
        case peerCredentialsFailed(Int32), readFailed(Int32), writeFailed(Int32), peerRejected
        case invalidHandshake, invalidResponse
    }

    private let socketPath: String
    private let timeout: TimeInterval
    private let identityProvider: HelperPeerIdentityProviding
    private let trustEvaluator: HelperPeerTrustEvaluating
    private let codec = HelperIPCFrameCodec()

    init(socketPath: String, timeout: TimeInterval = 5,
         identityProvider: HelperPeerIdentityProviding = RejectingPeerIdentityProvider(),
         trustEvaluator: HelperPeerTrustEvaluating) {
        self.socketPath = socketPath
        self.timeout = max(0.5, timeout)
        self.identityProvider = identityProvider
        self.trustEvaluator = trustEvaluator
    }

    func exchange(_ envelope: HelperIPCEnvelope) async throws -> HelperIPCEnvelope {
        try performExchange(envelope)
    }

    private func performExchange(_ envelope: HelperIPCEnvelope) throws -> HelperIPCEnvelope {
        #if canImport(Darwin) || canImport(Glibc)
        let fd = try connectSocket()
        defer { _ = shutdown(fd, Int32(SHUT_RDWR)); _ = close(fd) }
        let credentials = try readPeerCredentials(fd)
        let identity = try identityProvider.identity(for: credentials, socketFD: fd)
        // Re-read credentials from the same connected socket after csops. This binds the
        // code-signature lookup to the socket peer and rejects inconsistent peer snapshots.
        let confirmedCredentials = try readPeerCredentials(fd)
        guard HelperPeerIdentityBindingPolicy.credentialsAreStable(before: credentials, after: confirmedCredentials),
              HelperPeerIdentityBindingPolicy.identity(identity, matches: credentials),
              Self.auditTokenEvidenceIsSufficient(identity) else {
            throw SocketError.peerRejected
        }
        do { try trustEvaluator.verify(identity) } catch { throw SocketError.peerRejected }

        var handshake = HelperHandshake()
        let hello = try handshake.makeHello()
        try writeFrame(hello, fd: fd)
        let helloAck = try readFrame(fd: fd)
        do { try handshake.acceptHelloAck(helloAck) } catch { throw SocketError.invalidHandshake }

        let sessionBoundEnvelope = HelperIPCEnvelope(messageType: envelope.messageType,
            requestID: envelope.requestID, createdAt: envelope.createdAt,
            nonce: handshake.nonce, payload: envelope.payload)
        try writeFrame(sessionBoundEnvelope, fd: fd)
        let response = try readFrame(fd: fd)
        guard response.protocolVersion == HelperIPCEnvelope.currentVersion,
              response.requestID == envelope.requestID,
              response.nonce == handshake.nonce,
              abs(response.createdAt.timeIntervalSinceNow) <= 120 else { throw SocketError.invalidResponse }
        return response
        #else
        throw SocketError.unsupportedPlatform
        #endif
    }

    private func connectSocket() throws -> Int32 {
        guard socketPath.hasPrefix("/"), !socketPath.contains(".."), socketPath.utf8.count < 100 else {
            throw SocketError.invalidSocketPath
        }
        #if canImport(Glibc)
        let fd = socket(AF_UNIX, Int32(SOCK_STREAM.rawValue), 0)
        #else
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        #endif
        guard fd >= 0 else { throw SocketError.createFailed(errno) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        #if canImport(Darwin)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        #endif
        let pathBytes = Array(socketPath.utf8) + [0]
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.initializeMemory(as: UInt8.self, repeating: 0)
            raw.copyBytes(from: pathBytes)
        }
        var timeoutValue = timeval(tv_sec: Int(timeout), tv_usec: suseconds_t((timeout - floor(timeout)) * 1_000_000))
        _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeoutValue, socklen_t(MemoryLayout<timeval>.size))
        _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeoutValue, socklen_t(MemoryLayout<timeval>.size))
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else { let code = errno; _ = close(fd); throw SocketError.connectFailed(code) }
        return fd
    }

    private var one: Int32 = 1

    private static func auditTokenEvidenceIsSufficient(_ identity: HelperPeerIdentity) -> Bool {
        #if canImport(Darwin)
        return HelperPeerIdentityBindingPolicy.hasKernelPeerEvidence(identity)
        #else
        return true
        #endif
    }

    private func readPeerCredentials(_ fd: Int32) throws -> HelperSocketPeerCredentials {
        #if canImport(Darwin)
        var uid: uid_t = 0
        var gid: gid_t = 0
        guard getpeereid(fd, &uid, &gid) == 0 else { throw SocketError.peerCredentialsFailed(errno) }
        var pid: pid_t = -1
        var length = socklen_t(MemoryLayout<pid_t>.size)
        // XNU: SOL_LOCAL = 0, LOCAL_PEERPID = 0x002.
        guard getsockopt(fd, 0, 0x002, &pid, &length) == 0, pid > 0 else {
            throw SocketError.peerCredentialsFailed(errno)
        }
        return HelperSocketPeerCredentials(uid: UInt32(uid), gid: UInt32(gid), pid: Int32(pid))
        #elseif canImport(Glibc)
        struct LinuxPeerCred { var pid: pid_t; var uid: uid_t; var gid: gid_t }
        var value = LinuxPeerCred(pid: 0, uid: 0, gid: 0)
        var length = socklen_t(MemoryLayout<LinuxPeerCred>.size)
        guard getsockopt(fd, SOL_SOCKET, SO_PEERCRED, &value, &length) == 0 else {
            throw SocketError.peerCredentialsFailed(errno)
        }
        return HelperSocketPeerCredentials(uid: UInt32(value.uid), gid: UInt32(value.gid), pid: Int32(value.pid))
        #else
        throw SocketError.unsupportedPlatform
        #endif
    }

    private func writeFrame(_ envelope: HelperIPCEnvelope, fd: Int32) throws {
        let data = try codec.encode(envelope)
        try writeAll(data, fd: fd)
    }

    private func readFrame(fd: Int32) throws -> HelperIPCEnvelope {
        let header = try readExactly(4, fd: fd)
        let length = header.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard length > 0, length <= HelperIPCEnvelope.maximumFrameBytes else { throw HelperIPCCodecError.invalidLength }
        let body = try readExactly(Int(length), fd: fd)
        return try codec.decode(header + body)
    }

    private func writeAll(_ data: Data, fd: Int32) throws {
        try data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset < raw.count {
                let count = send(fd, base.advanced(by: offset), raw.count - offset, 0)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw SocketError.writeFailed(errno) }
                offset += count
            }
        }
    }

    private func readExactly(_ count: Int, fd: Int32) throws -> Data {
        var data = Data(count: count)
        try data.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset < count {
                let received = recv(fd, base.advanced(by: offset), count - offset, 0)
                if received < 0 && errno == EINTR { continue }
                guard received > 0 else { throw SocketError.readFailed(errno) }
                offset += received
            }
        }
        return data
    }
}

/// Synchronous server-side connection handler intended to run inside a separately built root helper.
/// This type does not create a launchd job or grant privileges by itself.
final class UnixDomainSocketServer {
    typealias RequestHandler = (_ envelope: HelperIPCEnvelope, _ context: HelperAuthenticatedPeerContext) throws -> HelperIPCEnvelope
    enum ServerError: Swift.Error { case invalidPath, socket(Int32), bind(Int32), chown(Int32), chmod(Int32), listen(Int32), accept(Int32), handshake, frame, peerIdentityChanged, replayedRequest }

    private let socketPath: String
    private let maximumConnections: Int
    private let socketMode: mode_t
    private let socketGroupID: UInt32
    private let handler: RequestHandler
    private let identityProvider: HelperPeerIdentityProviding
    private let trustEvaluator: HelperPeerTrustEvaluating
    private let codec = HelperIPCFrameCodec()
    private var listener: Int32 = -1
    private let slots: DispatchSemaphore
    private let diagnosticSink: ((HelperPeerAuthenticationDiagnostic) -> Void)?
    /// Process-local duplicate request-ID defense shared across accepted connections.
    private let replayGuard: HelperRequestReplayGuard

    init(socketPath: String, maximumConnections: Int = 8, socketMode: mode_t = 0o660, socketGroupID: UInt32 = 501,
         identityProvider: HelperPeerIdentityProviding = RejectingPeerIdentityProvider(),
         trustEvaluator: HelperPeerTrustEvaluating,
         diagnosticSink: ((HelperPeerAuthenticationDiagnostic) -> Void)? = nil,
         replayGuard: HelperRequestReplayGuard = HelperRequestReplayGuard(),
         handler: @escaping RequestHandler) {
        self.socketPath = socketPath
        self.maximumConnections = max(1, maximumConnections)
        self.socketMode = socketMode
        self.socketGroupID = socketGroupID
        self.identityProvider = identityProvider
        self.trustEvaluator = trustEvaluator
        self.handler = handler
        self.diagnosticSink = diagnosticSink
        self.replayGuard = replayGuard
        self.slots = DispatchSemaphore(value: max(1, maximumConnections))
    }

    /// Existing paths are never unlinked automatically. Installer/recovery code must remove stale sockets.
    func run() throws {
        guard socketPath.hasPrefix("/"), !socketPath.contains(".."), socketPath.utf8.count < 100 else { throw ServerError.invalidPath }
        #if canImport(Glibc)
        listener = socket(AF_UNIX, Int32(SOCK_STREAM.rawValue), 0)
        #else
        listener = socket(AF_UNIX, SOCK_STREAM, 0)
        #endif
        guard listener >= 0 else { throw ServerError.socket(errno) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        #if canImport(Darwin)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        #endif
        let pathBytes = Array(socketPath.utf8) + [0]
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.initializeMemory(as: UInt8.self, repeating: 0)
            raw.copyBytes(from: pathBytes)
        }
        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else { throw ServerError.bind(errno) }
        // The trusted installer provisions a root-owned, non-listable parent (0711) and
        // resolves socketGroupID from the installed App identity. Never use world-writable 0666.
        guard chown(socketPath, 0, gid_t(socketGroupID)) == 0 else { throw ServerError.chown(errno) }
        guard chmod(socketPath, socketMode) == 0 else { throw ServerError.chmod(errno) }
        try validateSocketNode()
        guard listen(listener, Int32(maximumConnections)) == 0 else { throw ServerError.listen(errno) }

        while true {
            let client = accept(listener, nil, nil)
            if client < 0 {
                if errno == EINTR { continue }
                throw ServerError.accept(errno)
            }
            guard slots.wait(timeout: .now()) == .success else { _ = close(client); continue }
            DispatchQueue.global(qos: .utility).async { [weak self] in
                defer { _ = close(client); self?.slots.signal() }
                self?.serve(client)
            }
        }
    }

    func stop() {
        if listener >= 0 { _ = shutdown(listener, Int32(SHUT_RDWR)); _ = close(listener); listener = -1 }
    }

    private func serve(_ fd: Int32) {
        let lifecycle = HelperPeerAuthenticationLifecycle()
        defer { lifecycle.close() }
        do {
            var timeoutValue = timeval(tv_sec: 5, tv_usec: 0)
            _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeoutValue, socklen_t(MemoryLayout<timeval>.size))
            _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeoutValue, socklen_t(MemoryLayout<timeval>.size))
            #if canImport(Darwin)
            var noSignal: Int32 = 1
            _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
            #endif
            let peer: HelperSocketPeerCredentials
            do {
                peer = try peerCredentials(fd)
                try lifecycle.advance(to: .credentialsVerified)
                emit(.init(stage: .credentials, outcome: .observed, credentials: peer, reasonCode: "peer_credentials_observed"))
            } catch {
                emit(.init(stage: .credentials, outcome: .rejected, reasonCode: "peer_credentials_unavailable"))
                throw error
            }
            let identity: HelperPeerIdentity
            do {
                identity = try identityProvider.identity(for: peer, socketFD: fd)
                let confirmedPeer = try peerCredentials(fd)
                guard HelperPeerIdentityBindingPolicy.credentialsAreStable(before: peer, after: confirmedPeer),
                      HelperPeerIdentityBindingPolicy.identity(identity, matches: peer),
                      Self.auditTokenEvidenceIsSufficient(identity) else {
                    throw ServerError.peerIdentityChanged
                }
                try lifecycle.advance(to: .codeIdentityVerified)
                emit(.init(stage: .codeIdentity, outcome: .accepted, credentials: peer, identity: identity, reasonCode: "peer_code_identity_read_and_reconfirmed"))
            } catch {
                emit(.init(stage: .codeIdentity, outcome: .rejected, credentials: peer, reasonCode: Self.identityFailureCode(error)))
                throw error
            }
            do {
                try trustEvaluator.verify(identity)
                try lifecycle.advance(to: .trustVerified)
                emit(.init(stage: .trustPolicy, outcome: .accepted, credentials: peer, identity: identity, reasonCode: "peer_trust_accepted"))
            } catch {
                emit(.init(stage: .trustPolicy, outcome: .rejected, credentials: peer, identity: identity, reasonCode: Self.trustFailureCode(error)))
                throw error
            }
            let hello: HelperIPCEnvelope
            let ack: HelperIPCEnvelope
            do {
                hello = try readFrame(fd)
                ack = try HelperHandshake.acceptHello(hello)
                try lifecycle.advance(to: .handshakeVerified)
                emit(.init(stage: .sessionHandshake, outcome: .accepted, credentials: peer,
                           identity: identity, reasonCode: "nonce_handshake_accepted"))
            } catch {
                emit(.init(stage: .sessionHandshake, outcome: .rejected, credentials: peer,
                           identity: identity, reasonCode: "nonce_handshake_rejected"))
                throw error
            }
            try writeFrame(ack, fd)
            guard let nonce = hello.nonce else { throw ServerError.handshake }
            try lifecycle.advance(to: .authenticated)
            let context = HelperAuthenticatedPeerContext(peer: peer, identity: identity,
                                                         sessionNonce: nonce, authenticatedAt: Date())
            let request = try readFrame(fd)
            guard HelperIPCServerRequestPolicy.allows(request.messageType),
                  request.nonce == nonce,
                  HelperIPCServerRequestPolicy.isFresh(request.createdAt) else { throw ServerError.handshake }
            guard replayGuard.accept(request.requestID) else {
                emit(.init(stage: .requestValidation, outcome: .rejected, credentials: peer,
                           identity: identity, reasonCode: "duplicate_request_id_rejected"))
                throw ServerError.replayedRequest
            }
            emit(.init(stage: .requestValidation, outcome: .accepted, credentials: peer,
                       identity: identity, reasonCode: "request_id_and_session_accepted"))
            let response = try handler(request, context)
            guard response.requestID == request.requestID,
                  response.nonce == context.sessionNonce else { throw ServerError.frame }
            try writeFrame(response, fd)
        } catch {
            lifecycle.fail()
            let rejected = HelperIPCEnvelope(messageType: .rejected)
            try? writeFrame(rejected, fd)
        }
    }

    private func emit(_ diagnostic: HelperPeerAuthenticationDiagnostic) {
        diagnosticSink?(diagnostic)
    }

    private static func identityFailureCode(_ error: Error) -> String {
        if let diagnostic = error as? HelperPeerIdentityDiagnosticError {
            return String(diagnostic.diagnosticCode.prefix(96))
        }
        if let serverError = error as? ServerError, case .peerIdentityChanged = serverError {
            return "peer_identity_evidence_incomplete_or_changed"
        }
        return "peer_identity_provider_failed"
    }

    private static func trustFailureCode(_ error: Error) -> String {
        guard let value = error as? HelperPeerTrustPolicy.TrustError else { return "peer_trust_rejected" }
        switch value {
        case .uidNotAllowed: return "peer_uid_not_allowed"
        case .gidNotAllowed: return "peer_gid_not_allowed"
        case .invalidCDHash: return "peer_cdhash_invalid"
        case .cdHashNotAllowed: return "peer_cdhash_not_pinned"
        case .invalidPID: return "peer_pid_invalid"
        }
    }

    private func validateSocketNode() throws {
        var info = stat()
        guard socketPath.withCString({ lstat($0, &info) }) == 0 else { throw ServerError.chmod(errno) }
        let isSocket = (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFSOCK)
        let mode = UInt16(info.st_mode & 0o777)
        guard HelperSocketRuntimePolicy.isExpectedSocket(ownerUID: UInt32(info.st_uid),
              groupID: UInt32(info.st_gid), mode: mode, expectedGroupID: socketGroupID,
              expectedMode: UInt16(socketMode & 0o777), isSocket: isSocket) else {
            throw ServerError.chmod(EACCES)
        }
        let parent = URL(fileURLWithPath: socketPath).deletingLastPathComponent().path
        let fd = parent.withCString { open($0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
        guard fd >= 0 else { throw ServerError.chmod(errno) }
        defer { _ = close(fd) }
        var parentInfo = stat()
        guard fstat(fd, &parentInfo) == 0,
              HelperSocketRuntimePolicy.isSafeParent(ownerUID: UInt32(parentInfo.st_uid),
                  mode: UInt16(parentInfo.st_mode & 0o777)) else { throw ServerError.chmod(EACCES) }
    }

    private static func auditTokenEvidenceIsSufficient(_ identity: HelperPeerIdentity) -> Bool {
        #if canImport(Darwin)
        return HelperPeerIdentityBindingPolicy.hasKernelPeerEvidence(identity)
        #else
        return true
        #endif
    }

    private func peerCredentials(_ fd: Int32) throws -> HelperSocketPeerCredentials {
        #if canImport(Darwin)
        var uid: uid_t = 0; var gid: gid_t = 0
        guard getpeereid(fd, &uid, &gid) == 0 else { throw ServerError.frame }
        var pid: pid_t = -1; var length = socklen_t(MemoryLayout<pid_t>.size)
        guard getsockopt(fd, 0, 0x002, &pid, &length) == 0, pid > 0 else { throw ServerError.frame }
        return HelperSocketPeerCredentials(uid: UInt32(uid), gid: UInt32(gid), pid: Int32(pid))
        #elseif canImport(Glibc)
        struct LinuxPeerCred { var pid: pid_t; var uid: uid_t; var gid: gid_t }
        var value = LinuxPeerCred(pid: 0, uid: 0, gid: 0); var length = socklen_t(MemoryLayout<LinuxPeerCred>.size)
        guard getsockopt(fd, SOL_SOCKET, SO_PEERCRED, &value, &length) == 0 else { throw ServerError.frame }
        return HelperSocketPeerCredentials(uid: UInt32(value.uid), gid: UInt32(value.gid), pid: Int32(value.pid))
        #else
        throw ServerError.frame
        #endif
    }

    private func writeFrame(_ envelope: HelperIPCEnvelope, _ fd: Int32) throws {
        let data = try codec.encode(envelope)
        try data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset < raw.count {
                let count = send(fd, base.advanced(by: offset), raw.count - offset, 0)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw ServerError.frame }
                offset += count
            }
        }
    }

    private func readFrame(_ fd: Int32) throws -> HelperIPCEnvelope {
        func read(_ count: Int) throws -> Data {
            var result = Data(count: count)
            try result.withUnsafeMutableBytes { raw in
                guard let base = raw.baseAddress else { return }
                var offset = 0
                while offset < count {
                    let received = recv(fd, base.advanced(by: offset), count - offset, 0)
                    if received < 0 && errno == EINTR { continue }
                    guard received > 0 else { throw ServerError.frame }
                    offset += received
                }
            }
            return result
        }
        let header = try read(4)
        let length = header.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard length > 0, length <= HelperIPCEnvelope.maximumFrameBytes else { throw ServerError.frame }
        return try codec.decode(header + read(Int(length)))
    }
}
