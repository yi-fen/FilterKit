import Foundation

/// Fails closed before opening the socket if installer-provisioned trust pins are incomplete.
enum HelperTrustConfigurationValidator {
    enum ValidationError: Error, Equatable { case noClientPins, noHelperPins, invalidUIDs, invalidSocketGroup, malformedPin, missingClientCodeIdentity }

    static func validate(_ manifest: HelperDeploymentManifest) throws {
        guard !manifest.allowedAppCDHashes.isEmpty else { throw ValidationError.noClientPins }
        guard !manifest.allowedHelperCDHashes.isEmpty else { throw ValidationError.noHelperPins }
        guard !manifest.allowedClientUIDs.isEmpty,
              manifest.allowedClientUIDs.allSatisfy({ $0 != 0 }),
              Set(manifest.allowedClientUIDs).count == manifest.allowedClientUIDs.count else {
            throw ValidationError.invalidUIDs
        }
        guard let bundleID = manifest.allowedClientBundleIdentifier,
              bundleID.range(of: "^[A-Za-z0-9-]+(\\.[A-Za-z0-9-]+)+$", options: .regularExpression) != nil,
              let teamID = manifest.allowedClientTeamIdentifier,
              teamID.range(of: "^[A-Z0-9]{10}$", options: .regularExpression) != nil else {
            throw ValidationError.missingClientCodeIdentity
        }
        guard let socketGroupID = manifest.socketGroupID, socketGroupID != 0 else {
            throw ValidationError.invalidSocketGroup
        }
        do {
            try HelperTrustPinSet.validatePins(manifest.allowedAppCDHashes)
            try HelperTrustPinSet.validatePins(manifest.allowedHelperCDHashes)
        } catch {
            throw ValidationError.malformedPin
        }
    }
}
