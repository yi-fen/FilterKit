import Foundation

/// Builds the immutable binding metadata for the first successful injection of a plugin.
/// The Fixed Owner is established once, while any supplied Additional Associations retain
/// their independent activation bits. The Filter.plist must describe exactly the enabled set.
enum PluginFirstInstallBindingPolicy {
    enum PolicyError: Error, Equatable {
        case invalidOwner
        case invalidAssociation
        case duplicateAssociation
        case ownerRepeatedAsAssociation
        case invalidFilter
        case filterTargetsMismatch
    }

    static func makeManifest(pluginID: UUID,
                             dylibFileName: String,
                             plistFileName: String,
                             dylibSHA256: String,
                             plistSHA256: String,
                             machOIdentitySHA256: String,
                             fixedOwnerBundleIdentifier: String,
                             additionalAssociations: [FilterKitManifestSoftAssociation],
                             filterPlistData: Data) throws -> FilterKitPluginManifest {
        let owner = fixedOwnerBundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidBundleIdentifier(owner) else { throw PolicyError.invalidOwner }

        var seen = Set<String>()
        for association in additionalAssociations {
            let value = association.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isValidBundleIdentifier(value) else { throw PolicyError.invalidAssociation }
            let key = HelperBundleIdentifierKey.make(value)
            guard key != HelperBundleIdentifierKey.make(owner) else {
                throw PolicyError.ownerRepeatedAsAssociation
            }
            guard seen.insert(key).inserted else { throw PolicyError.duplicateAssociation }
        }

        let filter = PluginFilterConfiguration.parse(filterPlistData)
        guard filter.parseState == .valid, !filter.bundles.isEmpty,
              filter.bundles.allSatisfy(isValidBundleIdentifier) else {
            throw PolicyError.invalidFilter
        }
        let filterKeys = HelperBundleIdentifierKey.set(filter.bundles)
        guard filterKeys.count == filter.bundles.count else { throw PolicyError.invalidFilter }
        let expectedEnabled = Set([HelperBundleIdentifierKey.make(owner)]).union(
            additionalAssociations.filter(\.isEnabled).map { HelperBundleIdentifierKey.make($0.bundleIdentifier) })
        guard filterKeys == expectedEnabled else { throw PolicyError.filterTargetsMismatch }

        let associations = additionalAssociations.sorted {
            HelperBundleIdentifierKey.make($0.bundleIdentifier) < HelperBundleIdentifierKey.make($1.bundleIdentifier)
        }
        let topology = FilterKitManifestBindingTopology(schemaVersion: 1,
            fixedOwnerBundleIdentifier: owner,
            fixedOwnerIsEnabled: true,
            additionalAssociations: associations)
        return FilterKitPluginManifest(schemaVersion: 4,
            pluginID: pluginID.uuidString,
            dylibFileName: dylibFileName,
            plistFileName: plistFileName,
            dylibSHA256: dylibSHA256.lowercased(),
            plistSHA256: plistSHA256.lowercased(),
            hardBoundBundleIdentifier: owner,
            softAssociatedBundleIdentifiers: associations.map(\.bundleIdentifier),
            machOIdentitySHA256: machOIdentitySHA256.lowercased(),
            softAssociations: associations,
            bindingTopology: topology)
    }

    static func isValidBundleIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 255 else { return false }
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count >= 2 && parts.allSatisfy { part in
            !part.isEmpty && part.utf8.count <= 63 &&
            (part.first?.isLetter == true || part.first?.isNumber == true || part.first == "_") &&
            part.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
        }
    }
}
