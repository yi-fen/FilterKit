import Foundation
#if canImport(Darwin)
import Darwin

/// Reads the peer's CDHash using XNU csops(CS_OPS_CDHASH).
/// This is a jailbreak/private-platform integration point and must be verified on each target OS.
final class DarwinPeerIdentityProvider: HelperPeerIdentityProviding {
    enum IdentityError: Swift.Error { case csopsUnavailable, cdHashReadFailed(Int32), invalidHashLength }

    // XNU bsd/sys/codesign.h: CS_OPS_CDHASH = 5; CS_CDHASH_LEN = 20.
    private static let csOpsCDHash: UInt32 = 5
    private static let cdHashLength = 20

    @_silgen_name("csops")
    private static func systemCSOps(_ pid: pid_t, _ operation: UInt32,
                                    _ output: UnsafeMutableRawPointer?, _ outputLength: Int) -> Int32

    func identity(for credentials: HelperSocketPeerCredentials) throws -> HelperPeerIdentity {
        guard credentials.pid > 0 else { throw IdentityError.csopsUnavailable }
        var bytes = [UInt8](repeating: 0, count: Self.cdHashLength)
        let result = bytes.withUnsafeMutableBytes { raw in
            Self.systemCSOps(pid_t(credentials.pid), Self.csOpsCDHash, raw.baseAddress, raw.count)
        }
        guard result == 0 else { throw IdentityError.cdHashReadFailed(errno) }
        guard bytes.count == Self.cdHashLength else { throw IdentityError.invalidHashLength }
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        return HelperPeerIdentity(uid: credentials.uid, gid: credentials.gid,
                                  pid: credentials.pid, cdHashHex: hex,
                                  pidVersion: nil, auditSessionID: nil)
    }

    func ownCDHash() throws -> String {
        let credentials = HelperSocketPeerCredentials(uid: UInt32(getuid()), gid: UInt32(getgid()), pid: Int32(getpid()))
        return try identity(for: credentials).cdHashHex
    }
}
#endif
