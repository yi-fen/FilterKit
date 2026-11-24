import Foundation

/// Adds a short-lived in-memory inventory cache around the runtime discovery provider.
/// Explicit refresh always bypasses the cache.
actor CachedAppDiscoveryProvider: AppDiscoveryProvider, AppDiscoveryRefreshing {
    private let source: AppDiscoveryProvider
    private let timeToLive: TimeInterval
    private let now: () -> Date
    private var cachedApps: [InstalledApp]?
    private var cachedAt: Date?

    init(source: AppDiscoveryProvider, timeToLive: TimeInterval = 60,
         now: @escaping () -> Date = Date.init) {
        self.source = source
        self.timeToLive = max(0, timeToLive)
        self.now = now
    }

    func scanInstalledApps() async throws -> [InstalledApp] {
        if let cachedApps, let cachedAt, now().timeIntervalSince(cachedAt) < timeToLive {
            return cachedApps
        }
        return try await refreshInstalledApps()
    }

    func refreshInstalledApps() async throws -> [InstalledApp] {
        let apps = try await source.scanInstalledApps()
        cachedApps = Self.deduplicatedAndSorted(apps)
        cachedAt = now()
        return cachedApps ?? []
    }

    func findApp(bundleIdentifier: String) async throws -> InstalledApp? {
        try await scanInstalledApps().first { $0.bundleIdentifier == bundleIdentifier }
    }

    func invalidateCache() async {
        cachedApps = nil
        cachedAt = nil
    }

    private static func deduplicatedAndSorted(_ apps: [InstalledApp]) -> [InstalledApp] {
        let unique = Dictionary(apps.map { ($0.bundleIdentifier, $0) },
                                uniquingKeysWith: { first, _ in first })
        return unique.values.sorted {
            let order = $0.displayName.localizedStandardCompare($1.displayName)
            return order == .orderedSame ? $0.bundleIdentifier < $1.bundleIdentifier : order == .orderedAscending
        }
    }
}
