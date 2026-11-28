import Foundation

/// APP-page activation may change an existing binding's enabled bit, but it may not
/// create or remove Additional App Associations. Relationship topology belongs to Plugin.
enum HelperAppPluginActivationTargetPolicy {
    enum Target: Equatable {
        case fixedOwner
        case additionalAssociation
    }

    enum PolicyError: Error, Equatable {
        case invalidBundleIdentifier
        case duplicateAssociation
        case notAssociated
    }

    static func validate(targetBundleIdentifier: String,
                         fixedOwnerBundleIdentifier: String,
                         additionalAssociations: [FilterKitManifestSoftAssociation]) throws -> Target {
        guard isValidBundleIdentifier(targetBundleIdentifier),
              isValidBundleIdentifier(fixedOwnerBundleIdentifier) else {
            throw PolicyError.invalidBundleIdentifier
        }

        let targetKey = HelperBundleIdentifierKey.make(targetBundleIdentifier)
        let ownerKey = HelperBundleIdentifierKey.make(fixedOwnerBundleIdentifier)
        if targetKey == ownerKey { return .fixedOwner }

        var seen = Set<String>()
        var found = false
        for association in additionalAssociations {
            guard isValidBundleIdentifier(association.bundleIdentifier) else {
                throw PolicyError.invalidBundleIdentifier
            }
            let key = HelperBundleIdentifierKey.make(association.bundleIdentifier)
            guard key != ownerKey, seen.insert(key).inserted else {
                throw PolicyError.duplicateAssociation
            }
            if key == targetKey { found = true }
        }
        guard found else { throw PolicyError.notAssociated }
        return .additionalAssociation
    }

    private static func isValidBundleIdentifier(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed == value, !value.isEmpty, value.utf8.count <= 255 else { return false }
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count >= 2 && parts.allSatisfy { part in
            !part.isEmpty && part.utf8.count <= 63 &&
            (part.first?.isLetter == true || part.first?.isNumber == true || part.first == "_") &&
            part.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
        }
    }
}
