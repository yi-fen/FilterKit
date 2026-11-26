import Foundation

/// Resolves verified FilterKit manifest associations against the current installed-app inventory.
/// This service is deliberately read-only: it does not rewrite manifests or migrate hard bindings.
final class ReadOnlyPluginAssociationReader: PluginAssociationReadingProvider {
    private let appDiscoveryProvider: AppDiscoveryProvider
    /// Warm inventory snapshot reused when the caller already holds one. When nil,
    /// the reader falls back to a fresh provider scan. This keeps association
    /// resolution from launching a second LaunchServices enumeration on a warm cache.
    private let snapshotApps: [InstalledApp]?

    init(appDiscoveryProvider: AppDiscoveryProvider, snapshotApps: [InstalledApp]? = nil) {
        self.appDiscoveryProvider = appDiscoveryProvider
        self.snapshotApps = snapshotApps
    }

    func readAssociations(from scanResult: PluginScanResult) async throws -> PluginAssociationReadResult {
        let installedApps: [InstalledApp]
        if let snapshotApps {
            installedApps = snapshotApps
        } else {
            installedApps = try await appDiscoveryProvider.scanInstalledApps()
        }
        let appsByBundleID = Dictionary(installedApps.map { ($0.bundleIdentifier, $0) },
                                        uniquingKeysWith: { first, _ in first })
        var snapshots: [PluginAssociationSnapshot] = []
        var skipped: [String] = []

        for item in scanResult.plugins where item.ownership == .filterKit {
            guard let rawPluginID = item.filterKitPluginID.flatMap(UUID.init(uuidString:)),
                  let hardBoundID = item.hardBoundBundleIdentifier,
                  Self.isValidBundleIdentifier(hardBoundID) else {
                skipped.append(item.id)
                continue
            }

            let normalizedSoftIDs = Set(item.softAssociatedBundleIdentifiers)
                .filter { Self.isValidBundleIdentifier($0) && $0 != hardBoundID }
            let hardBoundApp = appsByBundleID[hardBoundID]
            let sortedSoftIDs = normalizedSoftIDs.sorted()
            let softApps = sortedSoftIDs.compactMap { appsByBundleID[$0] }
            let missingSoftIDs = sortedSoftIDs.filter { appsByBundleID[$0] == nil }
            var effectiveIDs: [String] = []
            if hardBoundApp != nil { effectiveIDs.append(hardBoundID) }
            effectiveIDs.append(contentsOf: softApps.map(\.bundleIdentifier))

            snapshots.append(PluginAssociationSnapshot(
                pluginID: rawPluginID,
                hardBoundBundleIdentifier: hardBoundID,
                hardBoundApp: hardBoundApp,
                softAssociatedApps: softApps.sorted { $0.bundleIdentifier < $1.bundleIdentifier },
                missingSoftBundleIdentifiers: missingSoftIDs,
                effectiveBundleIdentifiers: Array(Set(effectiveIDs)).sorted(),
                state: hardBoundApp == nil ? .hardBoundAppMissing : .hardBoundAppInstalled
            ))
        }

        return PluginAssociationReadResult(
            readAt: Date(),
            installedAppCount: installedApps.count,
            snapshots: snapshots.sorted { $0.pluginID.uuidString < $1.pluginID.uuidString },
            skippedPluginIDs: skipped.sorted(),
            isReadOnly: true
        )
    }

    private static func isValidBundleIdentifier(_ value: String) -> Bool {
        guard value.count <= 255, !value.isEmpty else { return false }
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return false }
        return parts.allSatisfy { part in
            guard !part.isEmpty, part.count <= 63,
                  part.first?.isLetter == true || part.first?.isNumber == true else { return false }
            return part.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
        }
    }
}
