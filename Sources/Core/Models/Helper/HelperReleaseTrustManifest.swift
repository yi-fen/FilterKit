import Foundation

/// Versioned release identity record generated only after the final Helper has been signed.
/// A digest proves byte identity, not publisher provenance; publisher pins are explicit policy.
struct HelperReleaseTrustManifest: Codable, Equatable {
    enum PublisherPolicy: String, Codable { case integrityOnly, pinnedAppleIdentity }

    let schemaVersion: Int
    let releaseIdentifier: String
    let generation: UInt64
    let bundleIdentifier: String
    let helperVersion: String
    let helperCDHash: String
    let helperSHA256: String
    let publisherPolicy: PublisherPolicy
    let teamIdentifier: String?
    let leafCertificateSHA256: String?

    static let currentSchemaVersion = 1

    enum ValidationError: Error, Equatable {
        case unsupportedSchema, invalidRelease, invalidGeneration, invalidBundleIdentifier
        case invalidVersion, invalidCDHash, invalidSHA256, incompletePublisherPins, malformedPublisherPins
    }

    func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else { throw ValidationError.unsupportedSchema }
        guard !releaseIdentifier.isEmpty, releaseIdentifier.count <= 128,
              releaseIdentifier.range(of: "^[A-Za-z0-9._+-]+$", options: .regularExpression) != nil else {
            throw ValidationError.invalidRelease
        }
        guard generation > 0 else { throw ValidationError.invalidGeneration }
        let parts = bundleIdentifier.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2, parts.allSatisfy({ !$0.isEmpty && $0.first!.isLetter && $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" } }) else {
            throw ValidationError.invalidBundleIdentifier
        }
        guard !helperVersion.isEmpty, helperVersion.count <= 64 else { throw ValidationError.invalidVersion }
        guard HelperPolicy.isValidCDHash(helperCDHash) else { throw ValidationError.invalidCDHash }
        guard HelperPolicy.isValidHash(helperSHA256) else { throw ValidationError.invalidSHA256 }
        switch publisherPolicy {
        case .integrityOnly:
            guard teamIdentifier == nil, leafCertificateSHA256 == nil else { throw ValidationError.malformedPublisherPins }
        case .pinnedAppleIdentity:
            guard let team = teamIdentifier, team.range(of: "^[A-Z0-9]{10}$", options: .regularExpression) != nil,
                  let certificate = leafCertificateSHA256, HelperPolicy.isValidHash(certificate) else {
                throw ValidationError.incompletePublisherPins
            }
        }
    }

    func matches(_ bundle: HelperInstallerProvisioningBundle) -> Bool {
        do { try validate(); try bundle.validate() } catch { return false }
        return releaseIdentifier == bundle.releaseIdentifier && generation == bundle.generation &&
            bundleIdentifier == bundle.bundleIdentifier && helperVersion == bundle.helperVersion &&
            helperCDHash.caseInsensitiveCompare(bundle.helperCDHash) == .orderedSame
    }
}
