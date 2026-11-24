import Foundation

struct AppDiscoverySnapshot: Equatable {
    let scannedAt: Date
    let apps: [InstalledApp]
    let sourceDescription: String
    let isCached: Bool
}

enum AppDiscoveryError: Error, Equatable {
    case launchServicesUnavailable
    case workspaceUnavailable
    case enumerationUnavailable
    case accessRestricted
    case lsdProcessGuard
    case noReadableInventory
}

enum AppInventoryQuery {
    static func filter(_ apps: [InstalledApp], searchText: String = "",
                       showingSystemApps: Bool = false) -> [InstalledApp] {
        let visible = apps.filter {
            if showingSystemApps { return $0.systemClassification != .hidden }
            return $0.systemClassification == .user
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let matched = query.isEmpty ? visible : visible.filter {
            $0.displayName.localizedStandardContains(query) ||
            $0.bundleIdentifier.localizedStandardContains(query)
        }
        return matched.sorted {
            let comparison = $0.displayName.localizedStandardCompare($1.displayName)
            if comparison == .orderedSame { return $0.bundleIdentifier < $1.bundleIdentifier }
            return comparison == .orderedAscending
        }
    }
}
