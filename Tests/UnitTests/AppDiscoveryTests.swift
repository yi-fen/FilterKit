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

    func testProxyMetadataFallsBackPerFieldAndReadsPlistOnlyOnce() {
        let proxy = MetadataProxyMissingExecutableStub()
        let bundleURL = URL(fileURLWithPath: "/Applications/Example.app")
        var plistReads = 0
        let result = LaunchServicesAppDiscoveryProvider.resolveProxyMetadata(proxy: proxy, bundleURL: bundleURL) { _ in
            plistReads += 1
            return [
                "CFBundleExecutable": "ExampleBinary",
                "CFBundleShortVersionString": "1.2.3-fallback",
                "CFBundleVersion": "42-fallback",
                "CFBundleDisplayName": "Plist Name"
            ]
        }

        XCTAssertEqual(result.displayName, "Proxy Name")
        XCTAssertEqual(result.shortVersion, "2.0")
        XCTAssertEqual(result.buildVersion, "99")
        XCTAssertEqual(result.executableName, "ExampleBinary")
        XCTAssertEqual(result.iconName, "AppIconProxy")
        XCTAssertEqual(plistReads, 1)
        XCTAssertTrue(result.didReadInfoPlist)
    }

    func testProxyMetadataAvoidsPlistWhenEveryProxyFieldIsPresent() {
        let proxy = MetadataProxyStub(includeExecutable: true)
        let result = LaunchServicesAppDiscoveryProvider.resolveProxyMetadata(
            proxy: proxy, bundleURL: URL(fileURLWithPath: "/Applications/Example.app")) { _ in
                XCTFail("Info.plist should not be read when proxy metadata is complete")
                return [:]
            }
        XCTAssertEqual(result.executableName, "ExampleExec")
        XCTAssertFalse(result.didReadInfoPlist)
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

    func testStaleRefreshKeepsOldSnapshotUntilSuccessfulReplacement() async throws {
        let oldApp = InstalledApp(bundleIdentifier: "com.example.old", displayName: "Old", isSystemApp: false)
        let newApp = InstalledApp(bundleIdentifier: "com.example.new", displayName: "New", isSystemApp: false)
        let source = SwitchableAppDiscoveryProvider(initialApps: [oldApp])
        let cache = CachedAppDiscoveryProvider(source: source, timeToLive: 3_600)

        _ = try await cache.scanInstalledApps()
        await source.setNextResult([newApp])
        let refreshed = try await cache.markStaleAndRefresh()

        XCTAssertEqual(refreshed.map(\.bundleIdentifier), ["com.example.new"])
        XCTAssertEqual(cache.currentSnapshotSync()?.map(\.bundleIdentifier), ["com.example.new"])
    }

    func testFailedStaleRefreshRetainsLastSuccessfulSnapshotAndRetries() async throws {
        let oldApp = InstalledApp(bundleIdentifier: "com.example.old", displayName: "Old", isSystemApp: false)
        let newApp = InstalledApp(bundleIdentifier: "com.example.new", displayName: "New", isSystemApp: false)
        let source = SwitchableAppDiscoveryProvider(initialApps: [oldApp])
        let cache = CachedAppDiscoveryProvider(source: source, timeToLive: 3_600)

        _ = try await cache.scanInstalledApps()
        await source.setFailureNext()
        do {
            _ = try await cache.markStaleAndRefresh()
            XCTFail("Expected the stale refresh to fail")
        } catch {
            XCTAssertEqual(cache.currentSnapshotSync()?.map(\.bundleIdentifier), ["com.example.old"])
        }

        await source.setNextResult([newApp])
        let retried = try await cache.scanInstalledApps()
        XCTAssertEqual(retried.map(\.bundleIdentifier), ["com.example.new"])
    }

    func testR4PerformanceDiagnosticsTrackSelectorHitsAndSecondEntryFileReads() {
        let before = AppDiscoveryPerformanceDiagnostics.snapshot()
        AppDiscoveryPerformanceDiagnostics.recordProxy(selector: "localizedName", hit: true)
        AppDiscoveryPerformanceDiagnostics.recordProxy(selector: "localizedName", hit: false)
        AppDiscoveryPerformanceDiagnostics.recordInfoPlistRead()
        AppDiscoveryPerformanceDiagnostics.recordAppPageEntry(warmInventory: true)
        AppDiscoveryPerformanceDiagnostics.recordAppPageEntry(warmInventory: true)
        AppDiscoveryPerformanceDiagnostics.recordIconFileRead()
        let after = AppDiscoveryPerformanceDiagnostics.snapshot()

        XCTAssertEqual(after.proxyCalls["localizedName", default: 0] - before.proxyCalls["localizedName", default: 0], 2)
        XCTAssertEqual(after.proxyHits["localizedName", default: 0] - before.proxyHits["localizedName", default: 0], 1)
        XCTAssertEqual(after.plistReads - before.plistReads, 1)
        XCTAssertEqual(after.appPageEntries - before.appPageEntries, 2)
        XCTAssertEqual(after.warmInventoryEntries - before.warmInventoryEntries, 2)
        XCTAssertEqual(after.secondEntryIconFileReads - before.secondEntryIconFileReads, 1)
    }

    func testP239R1SeparatesPluginInventoryFromAttestationAndTracksSnapshotReuse() {
        let before = PluginInventoryPerformanceDiagnostics.snapshot()
        PluginInventoryPerformanceDiagnostics.recordInventoryScanStarted()
        PluginInventoryPerformanceDiagnostics.recordEnvironmentAssessment(milliseconds: 7)
        PluginInventoryPerformanceDiagnostics.recordPluginDirectoryScan(milliseconds: 19)
        PluginInventoryPerformanceDiagnostics.recordAssociationSnapshotConsumption()
        PluginInventoryPerformanceDiagnostics.recordAttestation(milliseconds: 31, outcome: .verified)
        PluginInventoryPerformanceDiagnostics.recordAttestation(milliseconds: 11, outcome: .unavailable)
        let after = PluginInventoryPerformanceDiagnostics.snapshot()

        XCTAssertEqual(after.inventoryScanCount - before.inventoryScanCount, 1)
        XCTAssertEqual(after.environmentAssessmentMilliseconds - before.environmentAssessmentMilliseconds, 7)
        XCTAssertEqual(after.pluginDirectoryScanMilliseconds - before.pluginDirectoryScanMilliseconds, 19)
        XCTAssertEqual(after.associationSnapshotConsumptions - before.associationSnapshotConsumptions, 1)
        XCTAssertEqual(after.attestationAttempts - before.attestationAttempts, 2)
        XCTAssertEqual(after.attestationVerified - before.attestationVerified, 1)
        XCTAssertEqual(after.attestationUnavailable - before.attestationUnavailable, 1)
        XCTAssertEqual(after.attestationMilliseconds - before.attestationMilliseconds, 42)
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

#if canImport(ObjectiveC)
private final class MetadataProxyStub: NSObject {
    private let includeExecutable: Bool
    init(includeExecutable: Bool) { self.includeExecutable = includeExecutable }
    @objc dynamic func localizedName() -> String { "Proxy Name" }
    @objc dynamic func shortVersionString() -> String { "2.0" }
    @objc dynamic func bundleVersion() -> String { "99" }
    @objc dynamic func iconName() -> String { "AppIconProxy" }
    @objc dynamic func executableName() -> String? { includeExecutable ? "ExampleExec" : nil }
}
#endif

#if canImport(ObjectiveC)
private final class MetadataProxyMissingExecutableStub: NSObject {
    @objc dynamic func localizedName() -> String { "Proxy Name" }
    @objc dynamic func shortVersionString() -> String { "2.0" }
    @objc dynamic func bundleVersion() -> String { "99" }
    @objc dynamic func iconName() -> String { "AppIconProxy" }
}
#endif

private actor SwitchableAppDiscoveryProvider: AppDiscoveryProvider {
    private var nextApps: [InstalledApp]
    private var shouldFailNext = false

    init(initialApps: [InstalledApp]) { nextApps = initialApps }
    func setNextResult(_ apps: [InstalledApp]) { nextApps = apps; shouldFailNext = false }
    func setFailureNext() { shouldFailNext = true }

    func scanInstalledApps() async throws -> [InstalledApp] {
        if shouldFailNext {
            shouldFailNext = false
            throw AppDiscoveryError.enumerationUnavailable
        }
        return nextApps
    }
    func findApp(bundleIdentifier: String) async throws -> InstalledApp? {
        try await scanInstalledApps().first { $0.bundleIdentifier == bundleIdentifier }
    }
}
