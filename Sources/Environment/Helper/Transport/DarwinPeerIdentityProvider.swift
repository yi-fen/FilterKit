import Foundation
#if canImport(Darwin)
import Darwin
import Security

/// Reads the peer CDHash and binds the lookup to the kernel LOCAL_PEERTOKEN snapshot.
/// LOCAL_PEERTOKEN is treated as opaque evidence: only the documented audit-token
/// euid/egid/pid/asid accessors are interpreted. No PID-version value is fabricated.
final class DarwinPeerIdentityProvider: HelperPeerIdentityProviding {
    enum IdentityError: HelperPeerIdentityDiagnosticError {
        case csopsUnavailable, cdHashReadFailed(Int32), invalidHashLength, emptyCDHash
        case auditTokenReadFailed(Int32), invalidAuditToken, auditTokenCredentialMismatch, auditTokenChanged
        case processGenerationReadFailed(Int32), processGenerationChanged, invalidProcessGeneration
        case codeSigningIdentityUnavailable, signingIdentifierUnavailable, teamIdentifierUnavailable

        var diagnosticCode: String {
            switch self {
            case .csopsUnavailable: return "peer_csops_unavailable"
            case .cdHashReadFailed: return "peer_cdhash_read_failed"
            case .invalidHashLength: return "peer_cdhash_length_invalid"
            case .emptyCDHash: return "peer_cdhash_empty"
            case .auditTokenReadFailed: return "peer_audit_token_read_failed"
            case .invalidAuditToken: return "peer_audit_token_length_invalid"
            case .auditTokenCredentialMismatch: return "peer_audit_token_credentials_mismatch"
            case .auditTokenChanged: return "peer_audit_token_changed"
            case .processGenerationReadFailed: return "peer_pid_generation_read_failed"
            case .processGenerationChanged: return "peer_pid_generation_changed"
            case .invalidProcessGeneration: return "peer_pid_generation_invalid"
            case .codeSigningIdentityUnavailable: return "peer_code_signing_identity_unavailable"
            case .signingIdentifierUnavailable: return "peer_signing_identifier_unavailable"
            case .teamIdentifierUnavailable: return "peer_team_identifier_unavailable"
            }
        }
    }

    // XNU bsd/sys/codesign.h: CS_OPS_CDHASH = 5; CS_CDHASH_LEN = 20.
    private static let csOpsCDHash: UInt32 = 5
    private static let cdHashLength = 20
    // XNU sys/un.h: SOL_LOCAL = 0, LOCAL_PEERTOKEN = 0x003.
    private static let localPeerToken: Int32 = 0x003
    private static let auditTokenWordCount = 8

    @_silgen_name("csops")
    private static func systemCSOps(_ pid: pid_t, _ operation: UInt32,
                                    _ output: UnsafeMutableRawPointer?, _ outputLength: Int) -> Int32

    func identity(for credentials: HelperSocketPeerCredentials) throws -> HelperPeerIdentity {
        try identity(for: credentials, socketFD: -1)
    }

    func identity(for credentials: HelperSocketPeerCredentials, socketFD: Int32) throws -> HelperPeerIdentity {
        guard credentials.pid > 0 else { throw IdentityError.csopsUnavailable }
        let beforeToken: [UInt32]? = socketFD >= 0 ? try readAuditToken(socketFD) : nil
        if let token = beforeToken {
            try validate(token: token, credentials: credentials)
        }

        let hex = try readCDHash(pid: pid_t(credentials.pid))

        let afterToken: [UInt32]? = socketFD >= 0 ? try readAuditToken(socketFD) : nil
        if let beforeToken, let afterToken {
            guard beforeToken == afterToken else { throw IdentityError.auditTokenChanged }
        }
        let tokenData: Data? = beforeToken.map { words in
            words.withUnsafeBytes { Data($0) }
        }
        let sessionID = beforeToken.map { $0[6] }
        // SecTaskCreateWithAuditToken consumes the complete kernel audit token, not a
        // caller-supplied PID. The signing identifier and Team ID are read from the task's
        // code-signing identity/validated entitlement, never inferred from CDHash.
        let signedIdentity: (bundleIdentifier: String, teamIdentifier: String)?
        if let beforeToken {
            signedIdentity = try readCodeSigningIdentity(auditTokenWords: beforeToken)
        } else {
            signedIdentity = nil
        }
        guard let signedIdentity else { throw IdentityError.codeSigningIdentityUnavailable }
        // PID generation counters are exposed only through XNU PRIVATE headers and remain
        // intentionally unavailable; the full audit token already binds this connection.
        return HelperPeerIdentity(uid: credentials.uid, gid: credentials.gid,
                                  pid: credentials.pid, cdHashHex: hex,
                                  pidVersion: nil, auditSessionID: sessionID,
                                  auditTokenDigest: tokenData.map(SHA256Digest.hex),
                                  verifiedCodeIdentifier: signedIdentity.bundleIdentifier,
                                  verifiedTeamIdentifier: signedIdentity.teamIdentifier)
    }

    /// Reads this Helper process's CDHash without requiring a connected client socket token.
    /// The previous implementation called `identity(for:)`, which necessarily failed closed
    /// because a self-identity lookup has no peer LOCAL_PEERTOKEN.
    func ownCDHash() throws -> String {
        try readCDHash(pid: getpid())
    }

    private func readCDHash(pid: pid_t) throws -> String {
        guard pid > 0 else { throw IdentityError.csopsUnavailable }
        var bytes = [UInt8](repeating: 0, count: Self.cdHashLength)
        let result = bytes.withUnsafeMutableBytes { raw in
            Self.systemCSOps(pid, Self.csOpsCDHash, raw.baseAddress, raw.count)
        }
        guard result == 0 else { throw IdentityError.cdHashReadFailed(errno) }
        guard bytes.count == Self.cdHashLength else { throw IdentityError.invalidHashLength }
        guard bytes.contains(where: { $0 != 0 }) else { throw IdentityError.emptyCDHash }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private func readCodeSigningIdentity(auditTokenWords: [UInt32]) throws -> (bundleIdentifier: String, teamIdentifier: String) {
        guard auditTokenWords.count == Self.auditTokenWordCount else {
            throw IdentityError.codeSigningIdentityUnavailable
        }
        var token = audit_token_t()
        let tokenSize = MemoryLayout<audit_token_t>.size
        guard tokenSize == MemoryLayout<UInt32>.size * Self.auditTokenWordCount else {
            throw IdentityError.codeSigningIdentityUnavailable
        }
        auditTokenWords.withUnsafeBytes { source in
            withUnsafeMutableBytes(of: &token) { destination in
                destination.copyBytes(from: source)
            }
        }
        // SecTask and its audit-token/entitlement accessors are macOS/Catalyst-only
        // public APIs; they are not exported by the iPhoneOS SDK. On iOS the
        // code-signing identifier/Team ID evidence is therefore recorded as
        // unavailable rather than inferred from the CDHash or fabricated. The
        // kernel audit-token double read and CDHash binding remain unchanged.
        #if os(macOS)
        guard let task = SecTaskCreateWithAuditToken(kCFAllocatorDefault, token) else {
            throw IdentityError.codeSigningIdentityUnavailable
        }
        guard let signingIdentifier = SecTaskCopySigningIdentifier(task, nil) as String?,
              !signingIdentifier.isEmpty else {
            throw IdentityError.signingIdentifierUnavailable
        }
        guard let teamIdentifier = SecTaskCopyValueForEntitlement(
            task, "com.apple.developer.team-identifier" as CFString, nil) as? String,
              teamIdentifier.range(of: "^[A-Z0-9]{10}$", options: .regularExpression) != nil else {
            throw IdentityError.teamIdentifierUnavailable
        }
        return (signingIdentifier, teamIdentifier)
        #else
        throw IdentityError.codeSigningIdentityUnavailable
        #endif
    }

    private func readAuditToken(_ fd: Int32) throws -> [UInt32] {
        var words = [UInt32](repeating: 0, count: Self.auditTokenWordCount)
        var length = socklen_t(MemoryLayout<UInt32>.size * words.count)
        let result = words.withUnsafeMutableBytes { raw in
            getsockopt(fd, 0, Self.localPeerToken, raw.baseAddress, &length)
        }
        guard result == 0 else { throw IdentityError.auditTokenReadFailed(errno) }
        guard Int(length) == MemoryLayout<UInt32>.size * Self.auditTokenWordCount else {
            throw IdentityError.invalidAuditToken
        }
        return words
    }

    private func validate(token: [UInt32], credentials: HelperSocketPeerCredentials) throws {
        guard token.count == Self.auditTokenWordCount else { throw IdentityError.invalidAuditToken }
        // audit_token_to_euid / audit_token_to_egid / audit_token_to_pid / audit_token_to_asid.
        guard token[1] == credentials.uid,
              token[2] == credentials.gid,
              Int32(bitPattern: token[5]) == credentials.pid else {
            throw IdentityError.auditTokenCredentialMismatch
        }
    }
}
#endif
