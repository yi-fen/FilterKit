import Foundation

/// Per-connection challenge/response. A fresh nonce is required for every socket connection.
struct HelperHandshake {
    enum State: Equatable { case idle, helloSent, authenticated, failed }
    enum Error: Swift.Error, Equatable { case invalidState, invalidMessage, nonceMismatch, staleMessage }

    private(set) var state: State = .idle
    private(set) var requestID: UUID?
    private(set) var nonce: String?

    mutating func makeHello(now: Date = Date()) throws -> HelperIPCEnvelope {
        guard state == .idle else { throw Error.invalidState }
        let challenge = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let id = UUID()
        nonce = challenge
        requestID = id
        state = .helloSent
        return HelperIPCEnvelope(messageType: .hello, requestID: id, createdAt: now, nonce: challenge)
    }

    mutating func acceptHelloAck(_ envelope: HelperIPCEnvelope) throws {
        guard state == .helloSent, let nonce, let requestID else { throw Error.invalidState }
        guard envelope.protocolVersion == HelperIPCEnvelope.currentVersion,
              envelope.messageType == .helloAck,
              envelope.requestID == requestID else {
            state = .failed
            throw Error.invalidMessage
        }
        guard envelope.nonce == nonce else {
            state = .failed
            throw Error.nonceMismatch
        }
        guard abs(envelope.createdAt.timeIntervalSinceNow) <= 120 else {
            state = .failed
            throw Error.staleMessage
        }
        state = .authenticated
    }

    static func acceptHello(_ envelope: HelperIPCEnvelope, now: Date = Date()) throws -> HelperIPCEnvelope {
        guard envelope.protocolVersion == HelperIPCEnvelope.currentVersion,
              envelope.messageType == .hello,
              let nonce = envelope.nonce,
              nonce.count >= 32, nonce.count <= 128,
              abs(envelope.createdAt.timeIntervalSince(now)) <= 120 else {
            throw Error.invalidMessage
        }
        return HelperIPCEnvelope(messageType: .helloAck, requestID: envelope.requestID,
                                 createdAt: now, nonce: nonce)
    }
}

/// Explicitly models the kernel credentials available from a connected AF_UNIX socket.
struct HelperSocketPeerCredentials: Equatable {
    let uid: UInt32
    let gid: UInt32
    let pid: Int32
}

protocol HelperPeerIdentityProviding {
    func identity(for credentials: HelperSocketPeerCredentials) throws -> HelperPeerIdentity
}

protocol HelperPeerTrustEvaluating {
    func verify(_ identity: HelperPeerIdentity) throws
}

struct HelperPeerTrustPolicy: HelperPeerTrustEvaluating {
    enum TrustError: Swift.Error { case uidNotAllowed, invalidCDHash, cdHashNotAllowed, invalidPID }
    let allowedUIDs: Set<UInt32>
    let allowedCDHashes: Set<String>

    func verify(_ identity: HelperPeerIdentity) throws {
        guard identity.pid > 0 else { throw TrustError.invalidPID }
        guard allowedUIDs.contains(identity.uid) else { throw TrustError.uidNotAllowed }
        guard identity.cdHashHex.range(of: "^[0-9a-fA-F]{40}$", options: .regularExpression) != nil else { throw TrustError.invalidCDHash }
        guard allowedCDHashes.contains(where: { $0.caseInsensitiveCompare(identity.cdHashHex) == .orderedSame }) else {
            throw TrustError.cdHashNotAllowed
        }
    }
}

/// A deliberately unavailable provider is the default: socket reachability never implies trust.
struct RejectingPeerIdentityProvider: HelperPeerIdentityProviding {
    enum ProviderError: Swift.Error { case platformIdentityNotConfigured }
    func identity(for credentials: HelperSocketPeerCredentials) throws -> HelperPeerIdentity {
        throw ProviderError.platformIdentityNotConfigured
    }
}

struct HelperAuthenticatedPeerContext: Equatable {
    let peer: HelperSocketPeerCredentials
    let identity: HelperPeerIdentity
    let sessionNonce: String
    let authenticatedAt: Date
}

enum HelperStartupIdentityGate {
    enum GateError: Swift.Error { case invalidHash, helperNotPinned }

    static func verify(ownCDHash: String, manifest: HelperDeploymentManifest) throws {
        guard ownCDHash.range(of: "^[0-9a-fA-F]{40}$", options: .regularExpression) != nil else {
            throw GateError.invalidHash
        }
        guard manifest.allowedHelperCDHashes.contains(where: { $0.caseInsensitiveCompare(ownCDHash) == .orderedSame }) else {
            throw GateError.helperNotPinned
        }
    }
}

/// Synchronous process-local replay guard for the blocking socket server.
/// A production helper should also persist recent request IDs or bind its journal to startup state.
final class HelperRequestReplayGuard {
    private let lock = NSLock()
    private let retention: TimeInterval
    private let capacity: Int
    private var seen: [UUID: Date] = [:]

    init(retention: TimeInterval = 600, capacity: Int = 4096) {
        self.retention = retention
        self.capacity = max(1, capacity)
    }

    func accept(_ requestID: UUID, now: Date = Date()) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        seen = seen.filter { now.timeIntervalSince($0.value) <= retention }
        guard seen[requestID] == nil else { return false }
        if seen.count >= capacity, let oldest = seen.min(by: { $0.value < $1.value })?.key {
            seen.removeValue(forKey: oldest)
        }
        seen[requestID] = now
        return true
    }
}
