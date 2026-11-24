import XCTest
@testable import FilterKit

final class AppDiscoveryTests: XCTestCase {
    func testInventorySearchMatchesNameAndBundleIdentifierAndHidesNonUserAppsByDefault() {
        let apps = [
            InstalledApp(bundleIdentifier: "com.example.zebra", displayName: "Zebra", systemClassification: .user),
            InstalledApp(bundleIdentifier: "com.apple.settings", displayName: "Settings", systemClassification: .system),
            InstalledApp(bundleIdentifier: "com.example.alpha", displayName: "Alpha", systemClassification: .user),
            InstalledApp(bundleIdentifier: "com.unknown.app", displayName: "Unknown", systemClassification: .unknown)
        ]

        XCTAssertEqual(AppInventoryQuery.filter(apps).map(\.bundleIdentifier),
                       ["com.example.alpha", "com.example.zebra"])
        XCTAssertEqual(AppInventoryQuery.filter(apps, searchText: "ZEB").map(\.bundleIdentifier),
                       ["com.example.zebra"])
        XCTAssertEqual(AppInventoryQuery.filter(apps, searchText: "com.example.alpha").count, 1)
        XCTAssertEqual(AppInventoryQuery.filter(apps, showingSystemApps: true).count, 4)
    }

    func testCacheUsesTTLAndExplicitRefreshBypassesCache() async throws {
        let source = CountingAppDiscoveryProvider()
        let clock = MutableDiscoveryClock()
        let cache = CachedAppDiscoveryProvider(source: source, timeToLive: 30, now: { clock.value })

        _ = try await cache.scanInstalledApps()
        _ = try await cache.scanInstalledApps()
        var calls = await source.callCount
        XCTAssertEqual(calls, 1)

        _ = try await cache.refreshInstalledApps()
        calls = await source.callCount
        XCTAssertEqual(calls, 2)

        clock.value = clock.value.addingTimeInterval(31)
        _ = try await cache.scanInstalledApps()
        calls = await source.callCount
        XCTAssertEqual(calls, 3)

        await cache.invalidateCache()
        _ = try await cache.scanInstalledApps()
        calls = await source.callCount
        XCTAssertEqual(calls, 4)
    }

    func testCacheDeduplicatesByBundleIdentifier() async throws {
        let duplicate = InstalledApp(bundleIdentifier: "com.example.app", displayName: "Example", isSystemApp: false)
        let source = StaticAppDiscoveryProvider(apps: [duplicate, duplicate])
        let cache = CachedAppDiscoveryProvider(source: source)
        let result = try await cache.scanInstalledApps()
        XCTAssertEqual(result.count, 1)
    }
}

private actor CountingAppDiscoveryProvider: AppDiscoveryProvider {
    private(set) var callCount = 0
    func scanInstalledApps() async throws -> [InstalledApp] {
        callCount += 1
        return [InstalledApp(bundleIdentifier: "com.example.app", displayName: "Example", isSystemApp: false)]
    }
    func findApp(bundleIdentifier: String) async throws -> InstalledApp? {
        try await scanInstalledApps().first { $0.bundleIdentifier == bundleIdentifier }
    }
}

private struct StaticAppDiscoveryProvider: AppDiscoveryProvider {
    let apps: [InstalledApp]
    func scanInstalledApps() async throws -> [InstalledApp] { apps }
    func findApp(bundleIdentifier: String) async throws -> InstalledApp? {
        apps.first { $0.bundleIdentifier == bundleIdentifier }
    }
}

private final class MutableDiscoveryClock {
    var value = Date(timeIntervalSince1970: 1_000)
}
