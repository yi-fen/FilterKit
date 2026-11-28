import Foundation

/// Stable, normalized lookup tables used by Plugin rows to render app associations.
/// Bundle IDs remain the identity; display names are presentation-only.
struct PluginAppDisplayIndex: Equatable {
    let namesByBundleIdentifier: [String: String]
    let namesByExecutable: [String: String]

    init(apps: [InstalledApp]) {
        namesByBundleIdentifier = Dictionary(apps.map {
            ($0.bundleIdentifier.lowercased(), Self.displayName(for: $0))
        }, uniquingKeysWith: { first, _ in first })
        namesByExecutable = Dictionary(apps.compactMap { app in
            guard let executable = app.executableName?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !executable.isEmpty else { return nil }
            return (executable.lowercased(), Self.displayName(for: app))
        }, uniquingKeysWith: { first, _ in first })
    }

    func appName(forBundleIdentifier bundleIdentifier: String) -> String {
        namesByBundleIdentifier[bundleIdentifier.lowercased()] ?? bundleIdentifier
    }

    func sortedUniqueNames(_ names: [String]) -> [String] {
        Array(Set(names)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private static func displayName(for app: InstalledApp) -> String {
        let name = app.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? app.bundleIdentifier : name
    }
}

