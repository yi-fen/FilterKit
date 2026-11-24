import Foundation

/// Fails closed before opening the socket if installer-provisioned trust pins are incomplete.
enum HelperTrustConfigurationValidator {
    enum ValidationError: Error, Equatable { case noClientPins, noHelperPins, invalidUIDs, malformedPin }

    static func validate(_ manifest: HelperDeploymentManifest) throws {
        guard !manifest.allowedAppCDHashes.isEmpty else { throw ValidationError.noClientPins }
        guard !manifest.allowedHelperCDHashes.isEmpty else { throw ValidationError.noHelperPins }
        guard !manifest.allowedClientUIDs.isEmpty,
              manifest.allowedClientUIDs.allSatisfy({ $0 != 0 }),
              Set(manifest.allowedClientUIDs).count == manifest.allowedClientUIDs.count else {
            throw ValidationError.invalidUIDs
        }
        do {
            try HelperTrustPinSet.validatePins(manifest.allowedAppCDHashes)
            try HelperTrustPinSet.validatePins(manifest.allowedHelperCDHashes)
        } catch {
            throw ValidationError.malformedPin
        }
    }
}
