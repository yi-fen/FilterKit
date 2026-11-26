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

    /// Non-scanning snapshot of the cached inventory, if present. Used to render
    /// a warm list before the background refresh completes; never triggers a
    /// LaunchServices enumeration.
    func currentSnapshot() -> [InstalledApp]? {
        cachedApps
    }

    /// Warm the inventory off the foreground path. The scan runs detached and
    /// any failure is ignored: the next foreground `scanInstalledApps()` retries
    /// normally. This keeps app startup non-blocking while giving the Apps and
    /// Plugins screens a warm cache when they appear.
    ///
    /// `nonisolated` so SwiftUI's `.task` Sendable closure can start the warm-up
    /// synchronously; the detached task hops back onto the actor to refresh.
    nonisolated func prewarm() {
        Task.detached { [weak self] in
            guard let self else { return }
            _ = try? await self.refreshInstalledApps()
        }
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

/// One short-lived inventory cache shared by the Apps and Plugins screens.
/// This mirrors R16's shared discovery service and prevents tab navigation from
/// triggering a second LaunchServices enumeration within the cache window.
enum AppDiscoveryProviderRegistry {
    static let shared = CachedAppDiscoveryProvider(
        source: LaunchServicesAppDiscoveryProvider(), timeToLive: 60)
}
