import Foundation

struct HelperPluginSoftAssociation: Codable, Equatable {
    let bundleIdentifier: String
    let isEnabled: Bool
}

enum HelperPluginFilterMutationAction: String, Codable, Equatable {
    case enableForApp
    case disableForApp
    case replaceSoftAssociations
}

/// Narrow intent-only request. It carries no filesystem path and no replacement plist bytes.
/// The Helper re-reads and validates all authoritative files itself.
struct HelperPluginFilterMutationRequest: Codable, Equatable {
    let requestID: UUID
    let pluginID: UUID
    let action: HelperPluginFilterMutationAction
    let dylibFileName: String
    let plistFileName: String
    let targetBundleIdentifier: String
    let expectedPlistSHA256: String
    let expectedManifestSHA256: String
    let createdAt: Date
    var desiredSoftAssociations: [HelperPluginSoftAssociation]? = nil

    func validateShape(now: Date = Date(), clockSkewLimit: TimeInterval = 120) -> Bool {
        guard requestID != UUID(uuidString: "00000000-0000-0000-0000-000000000000"),
              pluginID != UUID(uuidString: "00000000-0000-0000-0000-000000000000"),
              HelperPolicy.isSafeLeafName(dylibFileName), dylibFileName.lowercased().hasSuffix(".dylib"),
              HelperPolicy.isSafeLeafName(plistFileName), plistFileName.lowercased().hasSuffix(".plist"),
              String(dylibFileName.dropLast(6)).lowercased() == String(plistFileName.dropLast(6)).lowercased(),
              HelperPolicy.isValidHash(expectedPlistSHA256), HelperPolicy.isValidHash(expectedManifestSHA256),
              Self.isValidBundleIdentifier(targetBundleIdentifier),
              abs(now.timeIntervalSince(createdAt)) <= clockSkewLimit else { return false }
        if action == .replaceSoftAssociations {
            guard let desiredSoftAssociations, desiredSoftAssociations.count <= 512,
                  HelperBundleIdentifierKey.set(desiredSoftAssociations.map(\.bundleIdentifier)).count == desiredSoftAssociations.count,
                  desiredSoftAssociations.allSatisfy({ Self.isValidBundleIdentifier($0.bundleIdentifier) }) else { return false }
        } else if desiredSoftAssociations != nil { return false }
        return true
    }

    private static func isValidBundleIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 255 else { return false }
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count >= 2 && parts.allSatisfy { part in
            !part.isEmpty && part.count <= 63 &&
            part.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
        }
    }
}

enum HelperPluginFilterMutationDisposition: String, Codable, Equatable {
    case preparedForAtomicCommit
    case committed
    case alreadyInRequestedState
    case blocked
}

/// Public response deliberately contains hashes and status only, never root paths or file bytes.
struct HelperPluginFilterMutationResponse: Codable, Equatable {
    let requestID: UUID
    let pluginID: UUID
    let action: HelperPluginFilterMutationAction
    let targetBundleIdentifier: String
    let disposition: HelperPluginFilterMutationDisposition
    let reasonCode: String
    let previousPlistSHA256: String?
    let proposedPlistSHA256: String?
    let previousManifestSHA256: String?
    let proposedManifestSHA256: String?
    let completedAt: Date
}


/// Commit receipt contains no paths or file bytes. A nil transactionID means the requested
/// state was already present and no filesystem mutation was needed.
struct HelperPluginFilterMutationCommitReceipt: Codable, Equatable {
    let requestID: UUID
    let pluginID: UUID
    let action: HelperPluginFilterMutationAction
    let targetBundleIdentifier: String
    let transactionID: UUID?
    let disposition: HelperPluginFilterMutationDisposition
    let plistSHA256: String
    let manifestSHA256: String
    let completedAt: Date
}
