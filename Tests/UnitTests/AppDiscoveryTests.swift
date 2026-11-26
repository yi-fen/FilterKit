import XCTest
@testable import FilterKit

final class AppDiscoveryTests: XCTestCase {
    func testInventorySearchMatchesNameAndBundleIdentifierAndHidesSystemAppsByDefault() {
        let apps = [
            InstalledApp(bundleIdentifier: "com.example.zebra", displayName: "Zebra", systemClassification: .user),
            InstalledApp(bundleIdentifier: "com.apple.settings", displayName: "Settings", systemClassification: .system),
            InstalledApp(bundleIdentifier: "com.example.alpha", displayName: "Alpha", systemClassification: .user),
            InstalledApp(bundleIdentifier: "com.unknown.app", displayName: "Unknown", systemClassification: .unknown)
        ]

        XCTAssertEqual(AppInventoryQuery.filter(apps).map(\.bundleIdentifier),
                       ["com.example.alpha", "com.unknown.app", "com.example.zebra"])
        XCTAssertEqual(AppInventoryQuery.filter(apps, searchText: "ZEB").map(\.bundleIdentifier),
                       ["com.example.zebra"])
        XCTAssertEqual(AppInventoryQuery.filter(apps, searchText: "com.example.alpha").count, 1)
        XCTAssertEqual(AppInventoryQuery.filter(apps, showingSystemApps: true).count, 4)
    }

    func testTrollStoreContainerAppIsNotMisclassifiedAsSystem() {
        let appURL = URL(fileURLWithPath: "/var/containers/Bundle/Application/ABC123/Example.app")
        let classification = LaunchServicesAppDiscoveryProvider.classify(
            applicationType: "System", bundleID: "com.example.sideloaded",
            tags: nil, bundleURL: appURL)
        XCTAssertEqual(classification, .user)
    }

    func testR16PathRuleDoesNotHideThirdPartyBundleFromSystemInstallType() {
        let classification = LaunchServicesAppDiscoveryProvider.classify(
            applicationType: "System", bundleID: "org.example.legacy-id", tags: ["hidden"],
            bundleURL: URL(fileURLWithPath: "/var/containers/Bundle/Application/ABC123/Example.app"))
        XCTAssertEqual(classification, .user)
    }

    func testAppleSystemAppRemainsSystemClassified() {
        let classification = LaunchServicesAppDiscoveryProvider.classify(
            applicationType: "System", bundleID: "com.apple.Preferences", tags: nil,
            bundleURL: URL(fileURLWithPath: "/Applications/Preferences.app"))
        XCTAssertEqual(classification, .system)
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

    func testConcurrentScansShareOneInFlightSourceCall() async throws {
        let source = CountingAppDiscoveryProvider()
        let cache = CachedAppDiscoveryProvider(source: source)
        async let first = cache.scanInstalledApps()
        async let second = cache.scanInstalledApps()
        _ = try await (first, second)
        let calls = await source.callCount
        XCTAssertEqual(calls, 1)
    }

    func testCacheDeduplicatesByBundleIdentifier() async throws {
        let duplicate = InstalledApp(bundleIdentifier: "com.example.app", displayName: "Example", isSystemApp: false)
        let source = StaticAppDiscoveryProvider(apps: [duplicate, duplicate])
        let cache = CachedAppDiscoveryProvider(source: source)
        let result = try await cache.scanInstalledApps()
        XCTAssertEqual(result.count, 1)
    }

    func testCurrentSnapshotReflectsCacheAndInvalidation() async throws {
        let source = StaticAppDiscoveryProvider(apps: [
            InstalledApp(bundleIdentifier: "com.example.app", displayName: "Example", isSystemApp: false)
        ])
        let cache = CachedAppDiscoveryProvider(source: source)
        XCTAssertNil(await cache.currentSnapshot())
        _ = try await cache.scanInstalledApps()
        XCTAssertEqual(await cache.currentSnapshot()?.map(\.bundleIdentifier), ["com.example.app"])
        XCTAssertEqual(cache.currentSnapshotSync()?.map(\.bundleIdentifier), ["com.example.app"])
        await cache.invalidateCache()
        XCTAssertNil(await cache.currentSnapshot())
        XCTAssertNil(cache.currentSnapshotSync())
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
