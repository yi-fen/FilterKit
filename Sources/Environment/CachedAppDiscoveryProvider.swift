import Foundation

/// Adds a short-lived in-memory inventory cache around the runtime discovery provider.
/// Explicit refresh always bypasses the cache.
actor CachedAppDiscoveryProvider: AppDiscoveryProvider, AppDiscoveryRefreshing {
    private let source: AppDiscoveryProvider
    private let timeToLive: TimeInterval
    private let now: () -> Date
    private var cachedApps: [InstalledApp]?
    private var cachedAt: Date?
    /// Single in-flight enumeration shared by every concurrent caller, mirroring
    /// R16's `isLoading` + completion-waiters. Prewarm, Apps, and Plugins all
    /// await the same task instead of each launching a separate LaunchServices scan.
    private var inFlight: Task<[InstalledApp], Error>?
    /// Last successful inventory mirrored so a SwiftUI view model can read a warm
    /// snapshot synchronously from its initializer (mirroring R16's `currentResult()`
    /// in the view `init`), without awaiting the actor. The actor is the single
    /// writer; reads are nonisolated. `InstalledApp` is a value type, so a reader
    /// observes either the previous array reference or the new one, never a partial
    /// one. No lock: NSLock is unavailable from asynchronous actor contexts.
    private nonisolated(unsafe) var mirror: [InstalledApp]?

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
        return try await sharedRefresh().value
    }

    func refreshInstalledApps() async throws -> [InstalledApp] {
        try await sharedRefresh().value
    }

    func findApp(bundleIdentifier: String) async throws -> InstalledApp? {
        try await scanInstalledApps().first { $0.bundleIdentifier == bundleIdentifier }
    }

    func invalidateCache() async {
        cachedApps = nil
        cachedAt = nil
        mirror = nil
    }

    /// Non-scanning snapshot of the cached inventory, if present. Used to render
    /// a warm list before the background refresh completes; never triggers a
    /// LaunchServices enumeration.
    func currentSnapshot() -> [InstalledApp]? {
        cachedApps
    }

    /// Synchronous, non-scanning read of the last successful inventory. Usable from
    /// a view-model initializer before any `await` resumes; returns nil when no warm
    /// inventory exists yet (first cold launch). Never triggers an enumeration.
    nonisolated func currentSnapshotSync() -> [InstalledApp]? {
        mirror
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

    /// Reuse the existing in-flight enumeration, or start one. All concurrent
    /// callers await the same task; its result is written to the cache once on
    /// completion. A failed enumeration leaves the cache untouched for retry.
    private func sharedRefresh() -> Task<[InstalledApp], Error> {
        if let inFlight { return inFlight }
        let task = Task.detached(priority: .userInitiated) { [source] in
            try await source.scanInstalledApps()
        }
        inFlight = task
        Task { [weak self] in
            let result = await task.result
            await self?.finalizeRefresh(result: result)
        }
        return task
    }

    private func finalizeRefresh(result: Result<[InstalledApp], Error>) {
        inFlight = nil
        guard case .success(let apps) = result else { return }
        let sorted = Self.deduplicatedAndSorted(apps)
        cachedApps = sorted
        cachedAt = now()
        mirror = sorted
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
