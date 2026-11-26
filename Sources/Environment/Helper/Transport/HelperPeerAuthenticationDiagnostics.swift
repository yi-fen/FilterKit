import Foundation

/// Security diagnostics emitted by the Helper transport. CDHash is deliberately truncated;
/// the full pin remains in the protected trust manifest and is never copied to routine logs.
protocol HelperPeerIdentityDiagnosticError: Error {
    var diagnosticCode: String { get }
}

struct HelperPeerAuthenticationDiagnostic: Codable, Equatable {
    enum Stage: String, Codable { case credentials, codeIdentity, trustPolicy, sessionHandshake, requestValidation }
    enum Outcome: String, Codable { case observed, accepted, rejected }

    let timestamp: Date
    let stage: Stage
    let outcome: Outcome
    let peerUID: UInt32?
    let peerGID: UInt32?
    let peerPID: Int32?
    let cdHashPrefix: String?
    let pidVersion: UInt64?
    let auditSessionID: UInt32?
    let hasAuditTokenEvidence: Bool
    let hasProcessGenerationEvidence: Bool
    let reasonCode: String

    init(stage: Stage, outcome: Outcome, credentials: HelperSocketPeerCredentials? = nil,
         identity: HelperPeerIdentity? = nil, reasonCode: String, timestamp: Date = Date()) {
        self.timestamp = timestamp
        self.stage = stage
        self.outcome = outcome
        self.peerUID = identity?.uid ?? credentials?.uid
        self.peerGID = identity?.gid ?? credentials?.gid
        self.peerPID = identity?.pid ?? credentials?.pid
        self.cdHashPrefix = identity.map { String($0.cdHashHex.prefix(12)).lowercased() }
        self.pidVersion = identity?.pidVersion
        self.auditSessionID = identity?.auditSessionID
        self.hasAuditTokenEvidence = identity.map(HelperPeerIdentityBindingPolicy.hasKernelAuditTokenEvidence) ?? false
        self.hasProcessGenerationEvidence = identity.map(HelperPeerIdentityBindingPolicy.hasCompleteDarwinProcessGenerationEvidence) ?? false
        self.reasonCode = String(reasonCode.prefix(96))
    }
}

/// Pure policy used by startup self-check and unit tests. The socket node itself is checked
/// after bind/chown/chmod using lstat so symlinks and unexpected ownership cannot pass.
enum HelperSocketRuntimePolicy {
    static func isSafeParent(ownerUID: UInt32, mode: UInt16) -> Bool {
        ownerUID == 0 && (mode & 0o022) == 0 && (mode & 0o111) != 0
    }

    static func isExpectedSocket(ownerUID: UInt32, groupID: UInt32, mode: UInt16,
                                 expectedGroupID: UInt32, expectedMode: UInt16,
                                 isSocket: Bool) -> Bool {
        isSocket && ownerUID == 0 && groupID == expectedGroupID && mode == expectedMode
    }
}

/// Connection-scoped binding checks. Re-reading credentials from the same socket after
/// csops does not create an Audit Token, but detects inconsistent peer snapshots and
/// prevents accepting an identity whose UID/GID/PID differs from the kernel socket data.
enum HelperPeerIdentityBindingPolicy {
    static func credentialsAreStable(before: HelperSocketPeerCredentials,
                                     after: HelperSocketPeerCredentials) -> Bool {
        before == after && before.pid > 0
    }

    static func identity(_ identity: HelperPeerIdentity,
                         matches credentials: HelperSocketPeerCredentials) -> Bool {
        identity.uid == credentials.uid && identity.gid == credentials.gid &&
        identity.pid == credentials.pid && credentials.pid > 0
    }

    static func hasKernelAuditTokenEvidence(_ identity: HelperPeerIdentity) -> Bool {
        guard let digest = identity.auditTokenDigest else { return false }
        return digest.range(of: "^[0-9a-fA-F]{64}$", options: .regularExpression) != nil
    }

    /// Hard gate evidence on the public Darwin SDK: a complete kernel LOCAL_PEERTOKEN
    /// snapshot bound to a live PID. Process-generation counters live in XNU PRIVATE
    /// headers (`proc_uniqidentifierinfo`, flavors 17/18) that the public iOS SDK does
    /// not export, so generation is retained as an optional diagnostic enhancement rather
    /// than a compilable acceptance requirement.
    static func hasKernelPeerEvidence(_ identity: HelperPeerIdentity) -> Bool {
        identity.pid > 0 && hasKernelAuditTokenEvidence(identity)
    }

    static func hasCompleteDarwinProcessGenerationEvidence(_ identity: HelperPeerIdentity) -> Bool {
        hasKernelAuditTokenEvidence(identity) && identity.pid > 0 &&
        identity.pidVersion.map { $0 > 0 } == true
    }
}

/// A pure comparison policy so process-exit/PID-reuse races can be tested without
/// pretending that host tests exercise the Darwin kernel interface.
enum HelperPeerProcessGenerationBindingPolicy {
    static func isStable(before: UInt64?, after: UInt64?) -> Bool {
        guard let before, let after, before > 0, after > 0 else { return false }
        return before == after
    }
}


/// Per-connection authentication lifecycle. It contains no global peer state: every accepted
/// socket gets its own instance. The state machine is also used by host-side fault-injection
/// tests so failures can be exercised without claiming to emulate Darwin kernel APIs.
final class HelperPeerAuthenticationLifecycle {
    enum State: String, Equatable {
        case created, credentialsVerified, codeIdentityVerified, trustVerified
        case handshakeVerified, authenticated, failed, closed
    }

    enum LifecycleError: Error, Equatable { case invalidTransition(State, State) }
    private let lock = NSLock()
    private(set) var state: State = .created

    @discardableResult
    func advance(to next: State) throws -> State {
        lock.lock()
        defer { lock.unlock() }
        let allowed: Bool
        switch (state, next) {
        case (.created, .credentialsVerified),
             (.credentialsVerified, .codeIdentityVerified),
             (.codeIdentityVerified, .trustVerified),
             (.trustVerified, .handshakeVerified),
             (.handshakeVerified, .authenticated): allowed = true
        default: allowed = false
        }
        guard allowed else { throw LifecycleError.invalidTransition(state, next) }
        state = next
        return state
    }

    /// Failure and close are terminal and idempotent. A late error cannot resurrect a closed
    /// connection, and repeated cleanup from nested defer/catch paths is harmless.
    func fail() {
        lock.lock(); defer { lock.unlock() }
        if state != .closed && state != .authenticated { state = .failed }
    }

    func close() {
        lock.lock(); defer { lock.unlock() }
        state = .closed
    }

    func currentState() -> State {
        lock.lock(); defer { lock.unlock() }
        return state
    }
}
