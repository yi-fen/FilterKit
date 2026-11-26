import Foundation

/// Production runtime shell. It serves authenticated health and maintenance inspection, and
/// routes plugin-association Prepare/Commit requests through the dispatcher. Commit and general
/// deployment remain fail-closed behind independent release gates.
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
                                          allowedCDHashes: Set(manifest.allowedAppCDHashes),
                                          allowedGIDs: [manifest.socketGroupID ?? 0])
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
        let mutationConfiguration = try HelperPluginFilterMutationAuthorizer.Configuration(
            pluginDirectory: manifest.tweakInjectPath, dpkgInfoDirectories: packageInfoDirectories)
        let mutationAuthorizer = HelperPluginFilterMutationAuthorizer(configuration: mutationConfiguration)
        let associationTransaction = try HelperPluginFilterConfigurationTransaction(
            directoryPath: manifest.tweakInjectPath)
        let durableLedgerStore = try HelperDeploymentDurableLedgerStore(
            directoryPath: jbRoot + "/Library/FilterKit/Helper")
        let durableDeploymentLedger = HelperDeploymentIdempotencyLedger(durableStore: durableLedgerStore)
        let dispatcher = HelperRequestDispatcher(manifest: manifest, audit: audit,
            deploymentIdempotencyLedger: durableDeploymentLedger, deploymentLedgerStore: durableLedgerStore,
            deploymentPipeline: pipeline,
            pluginDirectory: manifest.tweakInjectPath, pluginFilterMutationAuthorizer: mutationAuthorizer,
            pluginAssociationTransaction: associationTransaction)
        let server = UnixDomainSocketServer(socketPath: manifest.socketPath,
            maximumConnections: HelperLifecycleProfile.conservativePersistent.maximumConcurrentConnections,
            socketMode: 0o660, socketGroupID: manifest.socketGroupID ?? 0, identityProvider: identityProvider, trustEvaluator: trust,
            diagnosticSink: { event in
                let peer: HelperPeerIdentity? = {
                    guard let uid = event.peerUID, let gid = event.peerGID, let pid = event.peerPID else { return nil }
                    return HelperPeerIdentity(uid: uid, gid: gid, pid: pid,
                        cdHashHex: event.cdHashPrefix ?? "", pidVersion: nil, auditSessionID: nil)
                }()
                let outcome: HelperAuditRecord.Outcome = event.outcome == .rejected ? .rejected : .accepted
                let reason = "auth.\(event.stage.rawValue).\(event.outcome.rawValue).\(event.reasonCode)"
                try? audit.append(HelperAuditRecord(peer: peer, outcome: outcome,
                    reasonCode: reason, timestamp: event.timestamp))
            }) { envelope, context in
                dispatcher.dispatch(envelope, context: context)
            }
        try server.run()
        throw RuntimeError.executionNotImplemented
        #else
        throw RuntimeError.jailbreakRootUnavailable
        #endif
    }
}
