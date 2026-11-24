import Foundation

/// Verifies release pins against installer provisioning and observations from platform tooling.
/// This is deliberately separate from CDHash-only running-process verification.
struct HelperReleaseTrustVerifier {
    enum Failure: Error, Equatable {
        case invalidManifest, provisioningMismatch, helperDigestMismatch, helperCDHashMismatch
        case publisherIdentityUnavailable, teamIdentifierMismatch, certificateFingerprintMismatch
    }

    func verify(manifest: HelperReleaseTrustManifest,
                provisioning: HelperInstallerProvisioningBundle,
                observedHelperSHA256: String,
                runningCDHash: String,
                observedTeamIdentifier: String? = nil,
                observedLeafCertificateSHA256: String? = nil) throws {
        do { try manifest.validate() } catch { throw Failure.invalidManifest }
        guard manifest.matches(provisioning) else { throw Failure.provisioningMismatch }
        guard HelperPolicy.isValidHash(observedHelperSHA256),
              observedHelperSHA256.caseInsensitiveCompare(manifest.helperSHA256) == .orderedSame else {
            throw Failure.helperDigestMismatch
        }
        guard HelperPolicy.isValidCDHash(runningCDHash),
              runningCDHash.caseInsensitiveCompare(manifest.helperCDHash) == .orderedSame else {
            throw Failure.helperCDHashMismatch
        }
        if manifest.publisherPolicy == .pinnedAppleIdentity {
            guard let team = observedTeamIdentifier, let certificate = observedLeafCertificateSHA256 else {
                throw Failure.publisherIdentityUnavailable
            }
            guard team == manifest.teamIdentifier else { throw Failure.teamIdentifierMismatch }
            guard HelperPolicy.isValidHash(certificate),
                  certificate.caseInsensitiveCompare(manifest.leafCertificateSHA256!) == .orderedSame else {
                throw Failure.certificateFingerprintMismatch
            }
        }
    }
}
