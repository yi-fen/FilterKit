import Foundation

/// Loads signed release metadata from root-owned files, then verifies the current executable
/// bytes and kernel-reported CDHash. It is read-only except for the accepted-generation Keychain update.
struct HelperSignedReleaseRuntimeLoader {
    enum Failure: Error, Equatable {
        case releaseAnchorsNotConfigured, executablePathUnavailable, provisioningInvalid
    }

    let anchors: [HelperReleaseSigningKey]
    let secureStore: HelperSecureManifestStore

    init(anchors: [HelperReleaseSigningKey] = HelperReleaseTrustAnchors.keys,
         secureStore: HelperSecureManifestStore = HelperSecureManifestStore(maximumBytes: 128 * 1024)) {
        self.anchors = anchors
        self.secureStore = secureStore
    }

    func verifyAndAccept(jbRoot: String, runningCDHash: String,
                         deploymentManifest: HelperDeploymentManifest,
                         pluginDirectory: String) throws -> HelperRuntimePreflight.Result {
        guard !anchors.isEmpty else { throw Failure.releaseAnchorsNotConfigured }
        return try HelperReleaseAcceptanceLock.withLock(root: jbRoot) {
            let base = jbRoot + "/Library/FilterKit/Helper"
            let signedData = try secureStore.readRootOwnedFile(
                path: base + "/release.signed.json", requiredMode: 0o600)
            let provisioningData = try secureStore.readRootOwnedFile(
                path: base + "/provisioning.json", requiredMode: 0o600)
            let signed = try JSONDecoder().decode(HelperSignedReleaseManifest.self, from: signedData)
            guard let provisioning = try? JSONDecoder().decode(HelperInstallerProvisioningBundle.self, from: provisioningData) else {
                throw Failure.provisioningInvalid
            }
            try provisioning.validate()
            guard provisioning.jbRootPath == jbRoot,
                  provisioning.tweakInjectPath == deploymentManifest.tweakInjectPath,
                  provisioning.stagingRootPath == deploymentManifest.stagingRootPath,
                  provisioning.socketPath == deploymentManifest.socketPath,
                  provisioning.generation == signed.payload.generation,
                  provisioning.releaseIdentifier == signed.payload.releaseIdentifier else {
                throw Failure.provisioningInvalid
            }
            guard let executablePath = Self.currentExecutablePath(),
                  HelperPolicy.isAbsoluteCleanPath(executablePath),
                  executablePath == jbRoot + "/usr/libexec/filterkit-helper" else {
                throw Failure.executablePathUnavailable
            }
            // Refuse a symlink, non-root-owned file, unexpected mode, or replaced on-disk image.
            let executable = try secureStore.readRootOwnedFile(path: executablePath,
                requiredMode: 0o755, maximumBytes: 64 * 1024 * 1024)
            let observedSHA256 = SHA256Digest.hex(executable)
            let verifier = HelperReleaseSignatureVerifier(keys: anchors, checker: HelperEd25519SignatureChecker())
            let antiRollback = HelperReleaseAntiRollbackGuard(store: try HelperReleaseGenerationStoreFactory.make())
            return try HelperRuntimePreflight().inspect(signedRelease: signed,
                signatureVerifier: verifier, antiRollback: antiRollback, provisioning: provisioning,
                observedHelperSHA256: observedSHA256, runningCDHash: runningCDHash,
                manifest: deploymentManifest, pluginDirectory: pluginDirectory)
        }
    }

    private static func currentExecutablePath() -> String? {
        Bundle.main.executableURL?.path
    }
}

/// Production anti-rollback storage exists only on Apple platforms with Keychain.
enum HelperReleaseGenerationStoreFactory {
    enum Failure: Error { case persistentStoreUnavailable }
    static func make() throws -> HelperReleaseGenerationStoring {
        #if canImport(Security)
        return KeychainHelperReleaseGenerationStore()
        #else
        throw Failure.persistentStoreUnavailable
        #endif
    }
}
