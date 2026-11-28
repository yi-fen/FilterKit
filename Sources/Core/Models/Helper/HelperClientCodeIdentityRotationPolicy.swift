import Foundation

/// Pure policy for an installer-authorized App CDHash rotation.
/// The caller must obtain `previous` from the authenticated, root-owned release record;
/// this value is not safe to construct from IPC or an untrusted App preference.
enum HelperClientCodeIdentityRotationPolicy {
    enum Failure: Error, Equatable {
        case invalidGeneration, generationNotMonotonic, bundleIdentifierChanged
        case teamIdentifierChanged, clientUIDChanged, jailbreakRootChanged
        case helperIdentityChanged, routeChanged, invalidCDHash, noRotation
    }

    static func validate(previous: HelperInstallerProvisioningBundle,
                         next: HelperInstallerProvisioningBundle) throws {
        do { try previous.validate(); try next.validate() }
        catch { throw Failure.invalidCDHash }
        guard next.generation > previous.generation else { throw Failure.generationNotMonotonic }
        guard next.generation == previous.generation + 1 else { throw Failure.invalidGeneration }
        guard previous.bundleIdentifier.caseInsensitiveCompare(next.bundleIdentifier) == .orderedSame else {
            throw Failure.bundleIdentifierChanged
        }
        guard let oldTeam = previous.teamIdentifier, let newTeam = next.teamIdentifier,
              !oldTeam.isEmpty, oldTeam == newTeam else { throw Failure.teamIdentifierChanged }
        guard previous.allowedClientUID == next.allowedClientUID,
              previous.socketGroupID == next.socketGroupID else { throw Failure.clientUIDChanged }
        guard previous.jbRootPath == next.jbRootPath else { throw Failure.jailbreakRootChanged }
        guard previous.helperCDHash.caseInsensitiveCompare(next.helperCDHash) == .orderedSame else {
            throw Failure.helperIdentityChanged
        }
        guard previous.routeIdentifier == next.routeIdentifier,
              previous.tweakInjectPath == next.tweakInjectPath,
              previous.stagingRootPath == next.stagingRootPath,
              previous.socketPath == next.socketPath else { throw Failure.routeChanged }
        let hashPattern = "^[0-9a-fA-F]{40}$"
        guard previous.appCDHash.range(of: hashPattern, options: .regularExpression) != nil,
              next.appCDHash.range(of: hashPattern, options: .regularExpression) != nil else {
            throw Failure.invalidCDHash
        }
        guard previous.appCDHash.caseInsensitiveCompare(next.appCDHash) != .orderedSame else {
            throw Failure.noRotation
        }
    }
}
