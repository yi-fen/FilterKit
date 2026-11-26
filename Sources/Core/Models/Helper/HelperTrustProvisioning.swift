import Foundation


/// App-bundled trust configuration. It contains only the separately signed Helper's CDHash,
/// so it can be embedded before the App itself is signed without a self-referential App CDHash.
struct HelperAppTrustConfiguration: Codable, Equatable {
    let schemaVersion: Int
    let bundleIdentifier: String
    let allowedHelperCDHashes: [String]
    let generation: UInt64
    /// Expected identity of the privileged Helper peer. Optional for decoding older schema-1
    /// configurations; newly generated provisioning always writes explicit root UID/GID pins.
    let allowedHelperUIDs: [UInt32]?
    let allowedHelperGIDs: [UInt32]?

    enum ValidationError: Error, Equatable { case unsupportedSchema, invalidBundleIdentifier, invalidHelperPins, invalidGeneration, invalidHelperCredentials }

    func validate() throws {
        guard schemaVersion == 1 else { throw ValidationError.unsupportedSchema }
        let components = bundleIdentifier.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count >= 2,
              components.allSatisfy({ !$0.isEmpty && $0.first!.isLetter && $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" } }) else {
            throw ValidationError.invalidBundleIdentifier
        }
        do { try HelperTrustPinSet.validatePins(allowedHelperCDHashes) }
        catch { throw ValidationError.invalidHelperPins }
        guard generation > 0 else { throw ValidationError.invalidGeneration }
        if let uids = allowedHelperUIDs {
            guard !uids.isEmpty, uids.allSatisfy({ $0 == 0 }), Set(uids).count == uids.count else {
                throw ValidationError.invalidHelperCredentials
            }
        }
        if let gids = allowedHelperGIDs {
            guard !gids.isEmpty, gids.allSatisfy({ $0 == 0 }), Set(gids).count == gids.count else {
                throw ValidationError.invalidHelperCredentials
            }
        }
    }
}

/// Exact code-signing pins supplied by a trusted installer/build pipeline.
/// This value is configuration, not a signature: callers must not populate it from IPC input.
struct HelperTrustPinSet: Codable, Equatable {
    let schemaVersion: Int
    let bundleIdentifier: String
    let allowedClientUIDs: [UInt32]
    let allowedAppCDHashes: [String]
    let allowedHelperCDHashes: [String]
    let generation: UInt64

    static let currentSchemaVersion = 1
    static let maximumPinsPerRole = 4

    enum ValidationError: Error, Equatable {
        case unsupportedSchema, invalidBundleIdentifier, invalidUIDs
        case missingPins, tooManyPins, malformedPin, duplicatePin, invalidGeneration
    }

    func makeDisabledManifest(routeIdentifier: String, jbRootPath: String, tweakInjectPath: String,
                              stagingRootPath: String, socketPath: String,
                              stagingOwnerUID: UInt32?, socketGroupID: UInt32 = 501) throws -> HelperDeploymentManifest {
        try validate()
        return HelperDeploymentManifest.disabledTemplate(routeIdentifier: routeIdentifier,
            jbRootPath: jbRootPath, tweakInjectPath: tweakInjectPath,
            stagingRootPath: stagingRootPath, socketPath: socketPath,
            appCDHashes: allowedAppCDHashes, helperCDHashes: allowedHelperCDHashes,
            allowedClientUIDs: allowedClientUIDs, stagingOwnerUID: stagingOwnerUID, socketGroupID: socketGroupID)
    }

    func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else { throw ValidationError.unsupportedSchema }
        let components = bundleIdentifier.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count >= 2,
              components.allSatisfy({ !$0.isEmpty && $0.first!.isLetter && $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" } }) else {
            throw ValidationError.invalidBundleIdentifier
        }
        guard !allowedClientUIDs.isEmpty, allowedClientUIDs.allSatisfy({ $0 != 0 }),
              Set(allowedClientUIDs).count == allowedClientUIDs.count else { throw ValidationError.invalidUIDs }
        try Self.validatePins(allowedAppCDHashes)
        try Self.validatePins(allowedHelperCDHashes)
        guard generation > 0 else { throw ValidationError.invalidGeneration }
    }

    static func validatePins(_ pins: [String]) throws {
        guard !pins.isEmpty else { throw ValidationError.missingPins }
        guard pins.count <= maximumPinsPerRole else { throw ValidationError.tooManyPins }
        for pin in pins {
            guard pin.range(of: "^[0-9a-fA-F]{40}$", options: .regularExpression) != nil else {
                throw ValidationError.malformedPin
            }
        }
        let normalized = pins.map { $0.lowercased() }
        guard Set(normalized).count == normalized.count else { throw ValidationError.duplicatePin }
    }

    /// Produces the App-bundled half of the trust configuration. This is intended to be
    /// embedded before the App is signed; the App's own CDHash is added to the root manifest
    /// only after final App signing by the trusted installer.
    func makeAppConfiguration() throws -> HelperAppTrustConfiguration {
        try validate()
        return HelperAppTrustConfiguration(schemaVersion: 1, bundleIdentifier: bundleIdentifier,
            allowedHelperCDHashes: allowedHelperCDHashes, generation: generation,
            allowedHelperUIDs: [0], allowedHelperGIDs: [0])
    }

    /// Checks that the root-owned Helper manifest matches installer-provisioned pins.
    /// It deliberately does not enable deployment.
    func validate(manifest: HelperDeploymentManifest) throws {
        try validate()
        guard manifest.schemaVersion == HelperDeploymentManifest.currentSchemaVersion,
              manifest.allowedClientUIDs == allowedClientUIDs,
              Self.normalized(manifest.allowedAppCDHashes) == Self.normalized(allowedAppCDHashes),
              Self.normalized(manifest.allowedHelperCDHashes) == Self.normalized(allowedHelperCDHashes),
              manifest.executionEnabled == false else {
            throw ValidationError.malformedPin
        }
    }

    private static func normalized(_ values: [String]) -> [String] {
        values.map { $0.lowercased() }.sorted()
    }
}

/// Cross-checks the post-sign installer record against the App-bundled Helper pins and
/// independently observed identities/credentials. This is a pure policy: platform code must
/// obtain observations from codesign/kernel APIs and must not accept them from IPC payloads.
enum HelperMaintenanceChannelCompatibilityPolicy {
    enum Failure: Error, Equatable {
        case invalidProvisioning, appTrustMismatch, appCDHashMismatch, helperCDHashMismatch
        case clientUIDMismatch, clientGIDMismatch, helperUIDMismatch, helperGIDMismatch
    }

    static func validate(installer: HelperInstallerProvisioningBundle,
                         appTrust: HelperAppTrustConfiguration,
                         observedAppCDHash: String,
                         observedHelperCDHash: String,
                         observedClientUID: UInt32,
                         observedClientGID: UInt32,
                         observedHelperUID: UInt32,
                         observedHelperGID: UInt32) throws {
        do { try installer.validate(); try appTrust.validate() }
        catch { throw Failure.invalidProvisioning }
        guard appTrust.bundleIdentifier == installer.bundleIdentifier,
              appTrust.generation == installer.generation,
              (appTrust.allowedHelperCDHashes.map { $0.lowercased() }).sorted() == [installer.helperCDHash.lowercased()] else {
            throw Failure.appTrustMismatch
        }
        guard HelperPolicy.isValidCDHash(observedAppCDHash),
              observedAppCDHash.caseInsensitiveCompare(installer.appCDHash) == .orderedSame else {
            throw Failure.appCDHashMismatch
        }
        guard HelperPolicy.isValidCDHash(observedHelperCDHash),
              observedHelperCDHash.caseInsensitiveCompare(installer.helperCDHash) == .orderedSame else {
            throw Failure.helperCDHashMismatch
        }
        guard observedClientUID == installer.allowedClientUID else { throw Failure.clientUIDMismatch }
        guard observedClientGID == installer.socketGroupID else { throw Failure.clientGIDMismatch }
        let allowedHelperUIDs = appTrust.allowedHelperUIDs ?? [0]
        let allowedHelperGIDs = appTrust.allowedHelperGIDs ?? [0]
        guard allowedHelperUIDs.contains(observedHelperUID), observedHelperUID == 0 else { throw Failure.helperUIDMismatch }
        guard allowedHelperGIDs.contains(observedHelperGID), observedHelperGID == 0 else { throw Failure.helperGIDMismatch }
    }
}

#if canImport(Darwin)
/// App-side factory. The installer supplies the exact Helper pins. The App checks its own
/// live code identity is readable; the Helper enforces the App's exact CDHash from its root-owned manifest.
enum HelperProductionTransportFactory {
    enum FactoryError: Error, Equatable { case wrongBundle, invalidPins, appCodeIdentityUnavailable, invalidAppCodeIdentity }

    static func makeCoordinator(socketPath: String, appTrust: HelperAppTrustConfiguration) throws -> HelperDeploymentCoordinator {
        do { try appTrust.validate() } catch { throw FactoryError.invalidPins }
        guard Bundle.main.bundleIdentifier == appTrust.bundleIdentifier else { throw FactoryError.wrongBundle }
        let provider = DarwinPeerIdentityProvider()
        // The App verifies the connected peer (the Helper) by kernel-reported PID/CDHash.
        // The Helper independently verifies this App's CDHash against its root-owned manifest.
        // Verify the running App's own code identity is readable before connecting. Its exact
        // CDHash is pinned by the root-owned Helper manifest (self-pinning inside the signed App
        // would be circular because embedding the hash changes the App signature).
        let ownHash: String
        do { ownHash = try provider.ownCDHash() } catch { throw FactoryError.appCodeIdentityUnavailable }
        guard HelperPolicy.isValidCDHash(ownHash) else { throw FactoryError.invalidAppCodeIdentity }
        let helperUIDs = appTrust.allowedHelperUIDs ?? [0]
        let helperGIDs = appTrust.allowedHelperGIDs ?? [0]
        let helperTrust = HelperPeerTrustPolicy(allowedUIDs: Set(helperUIDs), allowedCDHashes: Set(appTrust.allowedHelperCDHashes),
                                                 allowedGIDs: Set(helperGIDs))
        let transport = UnixDomainSocketTransport(socketPath: socketPath,
            identityProvider: provider, trustEvaluator: helperTrust)
        return HelperDeploymentCoordinator(transport: transport)
    }
}
#endif
