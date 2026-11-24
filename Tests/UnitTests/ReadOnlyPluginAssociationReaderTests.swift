import XCTest
@testable import FilterKit

final class ReadOnlyPluginAssociationReaderTests: XCTestCase {
    func testResolvesInstalledAndMissingSoftAssociationsWithoutChangingHardBinding() async throws {
        let pluginID = UUID()
        let scan = makeScan(pluginID: pluginID, hardBound: "com.example.source",
                            soft: ["com.example.secondary", "com.example.notinstalled"])
        let provider = StubAppDiscoveryProvider(apps: [
            InstalledApp(bundleIdentifier: "com.example.source", displayName: "Source", isSystemApp: false),
            InstalledApp(bundleIdentifier: "com.example.secondary", displayName: "Secondary", isSystemApp: false)
        ])

        let result = try await ReadOnlyPluginAssociationReader(appDiscoveryProvider: provider)
            .readAssociations(from: scan)

        let snapshot = try XCTUnwrap(result.snapshots.first)
        XCTAssertEqual(snapshot.hardBoundBundleIdentifier, "com.example.source")
        XCTAssertEqual(snapshot.hardBoundApp?.displayName, "Source")
        XCTAssertEqual(snapshot.softAssociatedApps.map(\.bundleIdentifier), ["com.example.secondary"])
        XCTAssertEqual(snapshot.missingSoftBundleIdentifiers, ["com.example.notinstalled"])
        XCTAssertEqual(snapshot.effectiveBundleIdentifiers, ["com.example.secondary", "com.example.source"])
        XCTAssertTrue(result.isReadOnly)
    }

    func testMissingHardBoundAppDoesNotMigrateIdentityOrBecomeEffective() async throws {
        let pluginID = UUID()
        let scan = makeScan(pluginID: pluginID, hardBound: "com.example.original", soft: ["com.example.available"])
        let provider = StubAppDiscoveryProvider(apps: [
            InstalledApp(bundleIdentifier: "com.example.available", displayName: "Available", isSystemApp: false)
        ])

        let result = try await ReadOnlyPluginAssociationReader(appDiscoveryProvider: provider)
            .readAssociations(from: scan)

        let snapshot = try XCTUnwrap(result.snapshots.first)
        XCTAssertEqual(snapshot.hardBoundBundleIdentifier, "com.example.original")
        XCTAssertNil(snapshot.hardBoundApp)
        XCTAssertEqual(snapshot.state, .hardBoundAppMissing)
        XCTAssertEqual(snapshot.effectiveBundleIdentifiers, ["com.example.available"])
    }

    private func makeScan(pluginID: UUID, hardBound: String, soft: [String]) -> PluginScanResult {
        let item = PluginScanItem(
            id: "Example.dylib", baseName: "Example", dylibFileName: "Example.dylib",
            plistFileName: "Example.plist", manifestFileName: "Example.fk.json",
            pairingState: .paired, binaryKind: .machO, ownership: .filterKit,
            filterKitPluginID: pluginID.uuidString, packageIdentifier: nil,
            dylibSHA256: String(repeating: "a", count: 64), plistSHA256: String(repeating: "b", count: 64),
            hardBoundBundleIdentifier: hardBound, softAssociatedBundleIdentifiers: soft, warnings: [],
            filterConfiguration: nil, managementPermission: nil
        )
        return PluginScanResult(scannedAt: Date(), scannedDirectory: "/plugins", directoryState: .resolved,
                                plugins: [item], issues: [], isReadOnly: true)
    }
}

private struct StubAppDiscoveryProvider: AppDiscoveryProvider {
    let apps: [InstalledApp]
    func scanInstalledApps() async throws -> [InstalledApp] { apps }
    func findApp(bundleIdentifier: String) async throws -> InstalledApp? {
        apps.first { $0.bundleIdentifier == bundleIdentifier }
    }
}
