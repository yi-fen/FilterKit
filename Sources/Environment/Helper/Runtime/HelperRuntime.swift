import Foundation

/// Production runtime shell. It can answer health checks; operation requests remain rejected.
/// The safe executor is compiled as an isolated module but is deliberately not dispatched here.
/// A valid manifest and a verified Helper CDHash are mandatory before the socket is opened.
final class FilterKitHelperRuntime {
    enum RuntimeError: Error {
        case jailbreakRootUnavailable, manifestRootMismatch, pathsOutsideJailbreakRoot
        case identityUnavailable, executionNotImplemented
    }

    private let pathProbe: LibrootRuntimeProbe
    private let manifestStore: HelperSecureManifestStore

    init(pathProbe: LibrootRuntimeProbe = LibrootRuntimeProbe(),
         manifestStore: HelperSecureManifestStore = HelperSecureManifestStore()) {
        self.pathProbe = pathProbe
        self.manifestStore = manifestStore
    }

    func run() throws -> Never {
        #if canImport(Darwin)
        let evidence = pathProbe.inspect()
        guard let jbRoot = evidence.jbrootPrefix else { throw RuntimeError.jailbreakRootUnavailable }
        let manifestPath = jbRoot + "/Library/FilterKit/Helper/manifest.json"
        let manifest = try manifestStore.read(path: manifestPath)
        guard manifest.jbRootPath == jbRoot else { throw RuntimeError.manifestRootMismatch }
        try HelperTrustConfigurationValidator.validate(manifest)
        let expectedHelperDirectory = jbRoot + "/Library/FilterKit/Helper"
        guard manifest.tweakInjectPath.hasPrefix(jbRoot + "/"),
              manifest.socketPath == expectedHelperDirectory + "/helper.sock",
              manifest.stagingRootPath.hasPrefix(jbRoot + "/") else { throw RuntimeError.pathsOutsideJailbreakRoot }

        let identityProvider = DarwinPeerIdentityProvider()
        let ownHash = try identityProvider.ownCDHash()
        try HelperStartupIdentityGate.verify(ownCDHash: ownHash, manifest: manifest)
        // Explicit read-only startup preflight: authenticate this running Helper and inspect
        // pending journals before creating the IPC listener. Recovery remains a separate,
        // authorized maintenance workflow; a dirty journal never enables deployment.
        // Production startup requires the signed release envelope, a compile-time trust anchor,
        // root-owned provisioning, executable SHA-256/CDHash agreement, and persistent rollback
        // state. There is deliberately no fallback to the legacy unsigned preflight path.
        let startupPreflight = try HelperSignedReleaseRuntimeLoader().verifyAndAccept(
            jbRoot: jbRoot, runningCDHash: ownHash, deploymentManifest: manifest,
            pluginDirectory: manifest.tweakInjectPath)
        _ = startupPreflight // Dispatcher independently rechecks recovery status per request.
        let trust = HelperPeerTrustPolicy(allowedUIDs: Set(manifest.allowedClientUIDs),
                                          allowedCDHashes: Set(manifest.allowedAppCDHashes))
        let audit = HelperAuditFileSink(path: jbRoot + "/Library/FilterKit/Helper/audit.jsonl",
                                        maximumBytes: HelperLifecycleProfile.conservativePersistent.maximumAuditFileBytes,
                                        retainedFiles: HelperLifecycleProfile.conservativePersistent.retainedAuditFiles)

        // Keep the authenticated status endpoint available even when recovery is pending or
        // the journal is invalid. The Dispatcher enters status-only mode and rejects all deploy
        // operations until a separately authorized recovery workflow is released.
        // Register the concrete root-side backend, but keep both independent execution gates
        // closed. P1-30 now provides a three-file transaction primitive and recovery journal;
        // Darwin/iOS and jailbreak-device validation plus explicit release approval are still required.
        guard let stagingUID = manifest.stagingOwnerUID else {
            throw RuntimeError.pathsOutsideJailbreakRoot
        }
        let packageInfoDirectories = [
            jbRoot + "/var/lib/dpkg/info",
            "/var/lib/dpkg/info",
            "/var/jb/var/lib/dpkg/info"
        ]
        let backendConfiguration = try HelperProductionDeploymentBackend.Configuration(
            pluginDirectory: manifest.tweakInjectPath,
            stagingRoot: manifest.stagingRootPath,
            stagingOwnerUID: stagingUID,
            dpkgInfoDirectories: packageInfoDirectories)
        let productionBackend = try HelperProductionDeploymentBackend(configuration: backendConfiguration)
        let pipeline = HelperDeploymentPipeline(backend: productionBackend)
        let dispatcher = HelperRequestDispatcher(manifest: manifest, audit: audit, deploymentPipeline: pipeline,
            pluginDirectory: manifest.tweakInjectPath)
        let server = UnixDomainSocketServer(socketPath: manifest.socketPath,
            maximumConnections: HelperLifecycleProfile.conservativePersistent.maximumConcurrentConnections,
            socketMode: 0o666, identityProvider: identityProvider, trustEvaluator: trust) { envelope, context in
                dispatcher.dispatch(envelope, context: context)
            }
        try server.run()
        throw RuntimeError.executionNotImplemented
        #else
        throw RuntimeError.jailbreakRootUnavailable
        #endif
    }
}
