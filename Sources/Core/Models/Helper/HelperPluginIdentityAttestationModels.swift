import Foundation

/// Read-only request. The App supplies leaf names and an expected manifest UUID only;
/// it never supplies paths, bytes, hashes, or ownership claims.
struct HelperPluginIdentityAttestationRequest: Codable, Equatable {
    let requestID: UUID
    let pluginID: UUID
    let dylibFileName: String
    let plistFileName: String
    let createdAt: Date

    func validate(now: Date = Date(), clockSkewLimit: TimeInterval = 120) -> Bool {
        requestID != UUID(uuidString: "00000000-0000-0000-0000-000000000000") &&
        pluginID != UUID(uuidString: "00000000-0000-0000-0000-000000000000") &&
        HelperPolicy.isSafeLeafName(dylibFileName) && dylibFileName.lowercased().hasSuffix(".dylib") &&
        HelperPolicy.isSafeLeafName(plistFileName) && plistFileName.lowercased().hasSuffix(".plist") &&
        String(dylibFileName.dropLast(6)).lowercased() == String(plistFileName.dropLast(6)).lowercased() &&
        abs(now.timeIntervalSince(createdAt)) <= clockSkewLimit
    }
}

enum HelperPluginIdentityAttestationStatus: String, Codable, Equatable {
    case verified
    case rejected
    case unavailable
}

/// Helper-authored evidence. This payload contains no filesystem paths and cannot authorize writes.
struct HelperPluginIdentityAttestation: Codable, Equatable {
    let requestID: UUID
    let status: HelperPluginIdentityAttestationStatus
    let reasonCode: String?
    let pluginID: UUID?
    let dylibFileName: String?
    let plistFileName: String?
    let dylibSHA256: String?
    let plistSHA256: String?
    let manifestSHA256: String?
    let machOIdentitySHA256: String?
    let hardBoundBundleIdentifier: String?
    let softAssociations: [FilterKitManifestSoftAssociation]?
    let filterConfiguration: PluginFilterConfiguration?
    let completedAt: Date

    static let maximumAge: TimeInterval = 120

    func isFresh(now: Date = Date(), maximumAge: TimeInterval = Self.maximumAge) -> Bool {
        let age = now.timeIntervalSince(completedAt)
        return age >= -5 && age <= maximumAge
    }

    var isVerified: Bool {
        guard status == .verified, let pluginID,
              let dylibFileName, HelperPolicy.isSafeLeafName(dylibFileName), dylibFileName.lowercased().hasSuffix(".dylib"),
              let plistFileName, HelperPolicy.isSafeLeafName(plistFileName), plistFileName.lowercased().hasSuffix(".plist"),
              String(dylibFileName.dropLast(6)).lowercased() == String(plistFileName.dropLast(6)).lowercased(),
              let dylibSHA256, HelperPolicy.isValidHash(dylibSHA256),
              let plistSHA256, HelperPolicy.isValidHash(plistSHA256),
              let manifestSHA256, HelperPolicy.isValidHash(manifestSHA256),
              let machOIdentitySHA256, HelperPolicy.isValidHash(machOIdentitySHA256),
              let hardBoundBundleIdentifier, Self.isValidBundleIdentifier(hardBoundBundleIdentifier),
              let softAssociations, softAssociations.allSatisfy({ Self.isValidBundleIdentifier($0.bundleIdentifier) }),
              Set(softAssociations.map(\.bundleIdentifier)).count == softAssociations.count,
              !softAssociations.contains(where: { $0.bundleIdentifier == hardBoundBundleIdentifier }),
              filterConfiguration?.parseState == .valid else { return false }
        return pluginID != UUID(uuidString: "00000000-0000-0000-0000-000000000000")
    }

    private static func isValidBundleIdentifier(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count >= 2 && parts.allSatisfy { part in
            !part.isEmpty && part.first!.isLetter && part.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
        }
    }
}
