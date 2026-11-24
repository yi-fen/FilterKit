import Foundation

enum PluginAssociationReadState: String, Codable {
    case hardBoundAppInstalled
    case hardBoundAppMissing
    case hardBoundIdentityUnavailable
}

/// A read-only projection of persisted association identity against the apps currently installed.
/// The hard-bound identity is never replaced when its app is absent.
struct PluginAssociationSnapshot: Codable, Equatable, Identifiable {
    let pluginID: UUID
    let hardBoundBundleIdentifier: String?
    let hardBoundApp: InstalledApp?
    let softAssociatedApps: [InstalledApp]
    let missingSoftBundleIdentifiers: [String]
    let effectiveBundleIdentifiers: [String]
    let state: PluginAssociationReadState

    var id: UUID { pluginID }
    var hasMissingAssociations: Bool {
        state == .hardBoundAppMissing || !missingSoftBundleIdentifiers.isEmpty
    }
}

struct PluginAssociationReadResult: Codable, Equatable {
    let readAt: Date
    let installedAppCount: Int
    let snapshots: [PluginAssociationSnapshot]
    let skippedPluginIDs: [String]
    let isReadOnly: Bool
}
