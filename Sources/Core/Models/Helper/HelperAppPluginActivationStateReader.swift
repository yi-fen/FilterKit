import Foundation

/// Resolves the authoritative persisted activation bit for one App from a Helper-read
/// FilterKit manifest. The fixed owner is not stored in `softAssociations`, so it must
/// be read from the schema-specific owner fields rather than defaulting to `false`.
/// Returns nil for unknown, duplicate, or internally inconsistent binding metadata.
enum HelperAppPluginActivationStateReader {
    static func enabledState(in manifest: FilterKitPluginManifest,
                             targetBundleIdentifier: String) -> Bool? {
        guard !targetBundleIdentifier.isEmpty else { return nil }
        guard let associations = manifest.softAssociations,
              let mirroredIdentifiers = manifest.softAssociatedBundleIdentifiers else { return nil }
        let associationIDs = associations.map(\.bundleIdentifier)
        let associationKeys = associationIDs.map(HelperBundleIdentifierKey.make)
        let mirroredKeys = mirroredIdentifiers.map(HelperBundleIdentifierKey.make)
        guard associationKeys.allSatisfy({ !$0.isEmpty }),
              Set(associationKeys).count == associationKeys.count,
              Set(mirroredKeys) == Set(associationKeys),
              Set(mirroredKeys).count == mirroredKeys.count else {
            return nil
        }
        let targetKey = HelperBundleIdentifierKey.make(targetBundleIdentifier)

        switch manifest.schemaVersion {
        case 3:
            guard let owner = manifest.hardBoundBundleIdentifier, !HelperBundleIdentifierKey.make(owner).isEmpty else { return nil }
            if targetKey == HelperBundleIdentifierKey.make(owner) { return true }
            let matches = associations.filter { HelperBundleIdentifierKey.make($0.bundleIdentifier) == targetKey }
            return matches.count == 1 ? matches[0].isEnabled : nil

        case 4:
            guard let owner = manifest.hardBoundBundleIdentifier,
                  let topology = manifest.bindingTopology,
                  topology.schemaVersion == 1,
                  HelperBundleIdentifierKey.make(topology.fixedOwnerBundleIdentifier ?? "") == HelperBundleIdentifierKey.make(owner),
                  topology.additionalAssociations.count == associations.count,
                  topology.additionalAssociations.allSatisfy({ candidate in
                      associations.contains { HelperBundleIdentifierKey.make($0.bundleIdentifier) == HelperBundleIdentifierKey.make(candidate.bundleIdentifier) && $0.isEnabled == candidate.isEnabled }
                  }),
                  HelperBundleIdentifierKey.set(topology.additionalAssociations.map(\.bundleIdentifier)) == Set(associationKeys),
                  topology.additionalAssociations.allSatisfy({ HelperBundleIdentifierKey.make($0.bundleIdentifier) != HelperBundleIdentifierKey.make(owner) }) else {
                return nil
            }
            if targetKey == HelperBundleIdentifierKey.make(owner) { return topology.fixedOwnerIsEnabled }
            let matches = topology.additionalAssociations.filter {
                HelperBundleIdentifierKey.make($0.bundleIdentifier) == targetKey
            }
            return matches.count == 1 ? matches[0].isEnabled : nil

        default:
            return nil
        }
    }
}
