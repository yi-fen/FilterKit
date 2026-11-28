import Foundation

/// Compares code-signing identity evidence collected by a trusted OS adapter.
/// CDHash, PID, UID and socket credentials are never interpreted as a Bundle ID or Team ID.
extension HelperPeerIdentityBindingPolicy {
    static func codeSigningIdentityMatches(_ identity: HelperPeerIdentity,
                                           bundleIdentifier: String,
                                           teamIdentifier: String) -> Bool {
        guard let observedBundle = identity.verifiedCodeIdentifier,
              let observedTeam = identity.verifiedTeamIdentifier,
              !observedTeam.isEmpty else { return false }
        return observedBundle.caseInsensitiveCompare(bundleIdentifier) == .orderedSame &&
            observedTeam == teamIdentifier
    }
}
