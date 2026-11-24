import Foundation

struct FilterKitManifestSoftAssociation: Codable, Equatable, Identifiable {
    let bundleIdentifier: String
    let isEnabled: Bool
    var id: String { bundleIdentifier }
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
}
