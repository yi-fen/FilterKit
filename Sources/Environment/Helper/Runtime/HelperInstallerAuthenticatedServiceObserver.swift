import Foundation

/// Result envelope for a service observer connected through the authenticated Helper IPC
/// transport. `peerIdentity` must be the OS-derived identity returned by the transport layer,
/// never decoded from the observer's message body. This validates provenance and freshness;
/// obtaining launchd state and hashing the live executable remain platform-adapter duties.
struct HelperInstallerAuthenticatedServiceObserver {
    struct Pin: Equatable {
        let bundleIdentifier: String
        let teamIdentifier: String
        let cdHash: String
        let observerCodeIdentitySHA256: String
        let auditUID: UInt32
    }

    struct Report: Equatable {
        let challenge: UUID
        let observation: HelperInstallerServiceObservation
    }

    enum ObserverError: Error, Equatable {
        case invalidPin, challengeMismatch, peerIdentityUnverified, identityMismatch
        case invalidObservation
    }

    static func validate(report: Report,
                         expectedChallenge: UUID,
                         authenticatedPeer: HelperPeerIdentity,
                         pin: Pin,
                         expectedHelperExecutableSHA256: String) throws -> HelperInstallerServiceObservation {
        guard pin.cdHash.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil,
              HelperPolicy.isValidHash(pin.observerCodeIdentitySHA256),
              HelperPolicy.isValidHash(expectedHelperExecutableSHA256),
              !pin.bundleIdentifier.isEmpty, !pin.teamIdentifier.isEmpty else {
            throw ObserverError.invalidPin
        }
        guard report.challenge == expectedChallenge else { throw ObserverError.challengeMismatch }
        guard authenticatedPeer.pid > 0,
              authenticatedPeer.uid == pin.auditUID,
              authenticatedPeer.auditTokenDigest.map(HelperPolicy.isValidHash) == true,
              authenticatedPeer.cdHashHex.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil,
              authenticatedPeer.verifiedCodeIdentifier != nil,
              authenticatedPeer.verifiedTeamIdentifier != nil else {
            throw ObserverError.peerIdentityUnverified
        }
        guard authenticatedPeer.cdHashHex == pin.cdHash,
              HelperPeerIdentityBindingPolicy.codeSigningIdentityMatches(
                authenticatedPeer,
                bundleIdentifier: pin.bundleIdentifier,
                teamIdentifier: pin.teamIdentifier) else {
            throw ObserverError.identityMismatch
        }
        guard report.observation.validates(
            expectedObserverCodeIdentitySHA256: pin.observerCodeIdentitySHA256,
            expectedExecutableSHA256: expectedHelperExecutableSHA256) else {
            throw ObserverError.invalidObservation
        }
        return report.observation
    }
}
