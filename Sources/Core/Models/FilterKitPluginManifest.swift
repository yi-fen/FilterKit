import Foundation

struct FilterKitManifestSoftAssociation: Codable, Equatable, Identifiable {
    let bundleIdentifier: String
    let isEnabled: Bool
    var id: String { bundleIdentifier }
}

/// Schema-4 binding state. Kept in the manifest file so both App and Helper targets
/// share the exact wire representation without depending on App-only view models.
struct FilterKitManifestBindingTopology: Codable, Equatable {
    let schemaVersion: Int
    let fixedOwnerBundleIdentifier: String?
    let fixedOwnerIsEnabled: Bool
    let additionalAssociations: [FilterKitManifestSoftAssociation]

    var enabledBundleIdentifiers: Set<String> {
        var result = Set(additionalAssociations.filter(\.isEnabled).map(\.bundleIdentifier))
        if fixedOwnerIsEnabled, let fixedOwnerBundleIdentifier { result.insert(fixedOwnerBundleIdentifier) }
        return result
    }
}

struct FilterKitPluginManifest: Codable, Equatable {
    let schemaVersion: Int
    let pluginID: String
    let dylibFileName: String
    let plistFileName: String
    let dylibSHA256: String
    let plistSHA256: String
    let hardBoundBundleIdentifier: String?
    let softAssociatedBundleIdentifiers: [String]?
    let machOIdentitySHA256: String?
    /// Present and authoritative in schema 3. Absent in legacy schema 1/2.
    var softAssociations: [FilterKitManifestSoftAssociation]? = nil
    /// Present in schema 4. Schema 1-3 remain backward-decodable.
    var bindingTopology: FilterKitManifestBindingTopology? = nil
}
