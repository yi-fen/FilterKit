import Foundation

enum PluginAssociationAvailability: String, Codable, Equatable {
    case available
    case unavailable
}

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

    /// Availability is a projection of the latest App Inventory, never persisted
    /// into the plugin manifest. Reinstalling the same Bundle ID therefore restores
    /// availability without rewriting ownership or association topology.
    func availability(for bundleIdentifier: String) -> PluginAssociationAvailability? {
        let key = HelperBundleIdentifierKey.make(bundleIdentifier)
        if let hardBoundBundleIdentifier,
           HelperBundleIdentifierKey.make(hardBoundBundleIdentifier) == key {
            return hardBoundApp == nil ? .unavailable : .available
        }
        guard softAssociatedApps.contains(where: { HelperBundleIdentifierKey.make($0.bundleIdentifier) == key })
                || missingSoftBundleIdentifiers.contains(where: { HelperBundleIdentifierKey.make($0) == key }) else { return nil }
        return missingSoftBundleIdentifiers.contains(where: { HelperBundleIdentifierKey.make($0) == key }) ? .unavailable : .available
    }

    var hasAnyAvailableAssociation: Bool {
        !effectiveBundleIdentifiers.isEmpty
    }
}

struct PluginAssociationReadResult: Codable, Equatable {
    let readAt: Date
    let installedAppCount: Int
    let snapshots: [PluginAssociationSnapshot]
    let skippedPluginIDs: [String]
    let isReadOnly: Bool
}
