import Foundation


/// App-bundled trust configuration. It contains only the separately signed Helper's CDHash,
/// so it can be embedded before the App itself is signed without a self-referential App CDHash.
struct HelperAppTrustConfiguration: Codable, Equatable {
    let schemaVersion: Int
    let bundleIdentifier: String
    let allowedHelperCDHashes: [String]
    let generation: UInt64

    enum ValidationError: Error, Equatable { case unsupportedSchema, invalidBundleIdentifier, invalidHelperPins, invalidGeneration }

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
                              stagingOwnerUID: UInt32?) throws -> HelperDeploymentManifest {
        try validate()
        return HelperDeploymentManifest.disabledTemplate(routeIdentifier: routeIdentifier,
            jbRootPath: jbRootPath, tweakInjectPath: tweakInjectPath,
            stagingRootPath: stagingRootPath, socketPath: socketPath,
            appCDHashes: allowedAppCDHashes, helperCDHashes: allowedHelperCDHashes,
            allowedClientUIDs: allowedClientUIDs, stagingOwnerUID: stagingOwnerUID)
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
            allowedHelperCDHashes: allowedHelperCDHashes, generation: generation)
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

#if canImport(Darwin)
/// App-side factory. The installer must provide the exact Helper pins; the App additionally
/// verifies its own live CDHash against the provisioned App pins before opening the socket.
enum HelperProductionTransportFactory {
    enum FactoryError: Error, Equatable { case wrongBundle, invalidPins }

    static func makeCoordinator(socketPath: String, appTrust: HelperAppTrustConfiguration) throws -> HelperDeploymentCoordinator {
        do { try appTrust.validate() } catch { throw FactoryError.invalidPins }
        guard Bundle.main.bundleIdentifier == appTrust.bundleIdentifier else { throw FactoryError.wrongBundle }
        let provider = DarwinPeerIdentityProvider()
        // The App verifies the connected peer (the Helper) by kernel-reported PID/CDHash.
        // The Helper independently verifies this App's CDHash against its root-owned manifest.
        let helperTrust = HelperPeerTrustPolicy(allowedUIDs: [0], allowedCDHashes: Set(appTrust.allowedHelperCDHashes))
        let transport = UnixDomainSocketTransport(socketPath: socketPath,
            identityProvider: provider, trustEvaluator: helperTrust)
        return HelperDeploymentCoordinator(transport: transport)
    }
}
#endif
