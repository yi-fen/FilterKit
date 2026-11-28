import Foundation

/// Enforces the Plugin-page boundary for a full-set soft-association transaction.
/// Plugin-page edits may add/remove relationships, but cannot change activation bits.
enum HelperPluginAssociationMutationPolicy {
    enum PolicyError: Error, Equatable {
        case invalidBundleIdentifier
        case duplicateAssociation
        case hardBoundImmutable
        case activationStateIsAppDetailOnly
        case tooManyAssociations
    }

    static func validate(original: [PluginSoftAssociation],
                         desired: [PluginSoftAssociation],
                         hardBoundBundleIdentifier: String) throws -> [PluginSoftAssociation] {
        guard PluginAssociationPlanResolver.isValidBundleIdentifier(hardBoundBundleIdentifier) else {
            throw PolicyError.invalidBundleIdentifier
        }
        guard desired.count <= 512 else { throw PolicyError.tooManyAssociations }

        func index(_ values: [PluginSoftAssociation]) throws -> [String: Bool] {
            var result: [String: Bool] = [:]
            for value in values {
                guard PluginAssociationPlanResolver.isValidBundleIdentifier(value.bundleIdentifier) else {
                    throw PolicyError.invalidBundleIdentifier
                }
                let key = HelperBundleIdentifierKey.make(value.bundleIdentifier)
                guard key != HelperBundleIdentifierKey.make(hardBoundBundleIdentifier) else {
                    throw PolicyError.hardBoundImmutable
                }
                guard result[key] == nil else { throw PolicyError.duplicateAssociation }
                result[key] = value.isEnabled
            }
            return result
        }

        let old = try index(original)
        let new = try index(desired)
        for (bundleID, enabled) in new {
            if let prior = old[bundleID] {
                guard prior == enabled else { throw PolicyError.activationStateIsAppDetailOnly }
            } else if enabled {
                throw PolicyError.activationStateIsAppDetailOnly
            }
        }
        // Removing a relationship is a Plugin-page operation even when it was active.
        // The privileged Helper must atomically remove that Bundle from Filter.plist and
        // remove the relationship from Manifest in the same transaction.
        return desired.sorted { $0.bundleIdentifier < $1.bundleIdentifier }
    }
}
