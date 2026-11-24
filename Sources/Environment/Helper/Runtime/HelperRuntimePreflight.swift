import Foundation

/// Read-only startup preflight. It verifies the running Helper identity and inspects journals;
/// it never repairs, removes, renames, or activates files.
struct HelperRuntimePreflight {
    enum Failure: Error, Equatable { case identityRejected }
    struct Result: Equatable {
        let helperIdentityVerified: Bool
        let recoveryDetail: HelperStartupRecoveryCheck.Detail
        var permitsNormalDeployment: Bool {
            helperIdentityVerified && recoveryDetail == .clean
        }
    }

    /// Signed release entry point. Signature and anti-rollback checks run before trusting any
    /// release pins. The accepted generation is persisted only after identity checks succeed.
    func inspect(signedRelease: HelperSignedReleaseManifest,
                 signatureVerifier: HelperReleaseSignatureVerifier,
                 antiRollback: HelperReleaseAntiRollbackGuard,
                 provisioning: HelperInstallerProvisioningBundle,
                 observedHelperSHA256: String,
                 runningCDHash: String,
                 observedTeamIdentifier: String? = nil,
                 observedLeafCertificateSHA256: String? = nil,
                 manifest: HelperDeploymentManifest,
                 pluginDirectory: String) throws -> Result {
        try signatureVerifier.verify(signedRelease)
        try antiRollback.check(signedRelease.payload)
        try HelperReleaseTrustVerifier().verify(manifest: signedRelease.payload, provisioning: provisioning,
            observedHelperSHA256: observedHelperSHA256, runningCDHash: runningCDHash,
            observedTeamIdentifier: observedTeamIdentifier,
            observedLeafCertificateSHA256: observedLeafCertificateSHA256)
        let result = try inspect(runningCDHash: runningCDHash, manifest: manifest, pluginDirectory: pluginDirectory)
        try antiRollback.accept(signedRelease.payload)
        return result
    }

    /// Stronger release-aware entry point. The caller supplies observations obtained from the
    /// running executable and platform signing metadata; this method performs no filesystem writes.
    func inspect(releaseTrust: HelperReleaseTrustManifest,
                 provisioning: HelperInstallerProvisioningBundle,
                 observedHelperSHA256: String,
                 runningCDHash: String,
                 observedTeamIdentifier: String? = nil,
                 observedLeafCertificateSHA256: String? = nil,
                 manifest: HelperDeploymentManifest,
                 pluginDirectory: String) throws -> Result {
        try HelperReleaseTrustVerifier().verify(manifest: releaseTrust, provisioning: provisioning,
            observedHelperSHA256: observedHelperSHA256, runningCDHash: runningCDHash,
            observedTeamIdentifier: observedTeamIdentifier,
            observedLeafCertificateSHA256: observedLeafCertificateSHA256)
        return try inspect(runningCDHash: runningCDHash, manifest: manifest, pluginDirectory: pluginDirectory)
    }

    func inspect(runningCDHash: String, manifest: HelperDeploymentManifest,
                 pluginDirectory: String,
                 signatureVerifier: HelperCodeSignatureVerifier = HelperCodeSignatureVerifier()) throws -> Result {
        do {
            try signatureVerifier.verifyRunningHelper(cdHash: runningCDHash,
                                                       allowedCDHashes: manifest.allowedHelperCDHashes)
        } catch {
            throw Failure.identityRejected
        }
        let recovery = HelperStartupRecoveryCheck().inspectDetailed(pluginDirectory: pluginDirectory)
        return Result(helperIdentityVerified: true, recoveryDetail: recovery)
    }
}
