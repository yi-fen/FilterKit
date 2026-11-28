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

    func testBundleIdentifierMatchingIsCaseInsensitiveAndPreservesManifestIdentity() async throws {
        let pluginID = UUID()
        let scan = makeScan(pluginID: pluginID, hardBound: "com.example.source", soft: ["com.example.secondary"])
        let provider = StubAppDiscoveryProvider(apps: [
            InstalledApp(bundleIdentifier: "COM.EXAMPLE.SOURCE", displayName: "Source", isSystemApp: false),
            InstalledApp(bundleIdentifier: "COM.EXAMPLE.SECONDARY", displayName: "Secondary", isSystemApp: false)
        ])
        let result = try await ReadOnlyPluginAssociationReader(appDiscoveryProvider: provider)
            .readAssociations(from: scan)
        let snapshot = try XCTUnwrap(result.snapshots.first)
        XCTAssertEqual(snapshot.hardBoundBundleIdentifier, "com.example.source")
        XCTAssertEqual(snapshot.hardBoundApp?.bundleIdentifier, "COM.EXAMPLE.SOURCE")
        XCTAssertEqual(snapshot.softAssociatedApps.map(\.bundleIdentifier), ["COM.EXAMPLE.SECONDARY"])
        XCTAssertEqual(snapshot.effectiveBundleIdentifiers, ["COM.EXAMPLE.SECONDARY", "COM.EXAMPLE.SOURCE"])
        XCTAssertEqual(snapshot.availability(for: "Com.Example.Source"), .available)
        XCTAssertEqual(snapshot.availability(for: "com.example.secondary"), .available)
    }

    func testCaseVariantDuplicateSoftAssociationsFailClosed() async throws {
        let pluginID = UUID()
        let scan = makeScan(pluginID: pluginID, hardBound: "com.example.source",
            soft: ["com.example.target", "COM.EXAMPLE.TARGET"])
        let provider = StubAppDiscoveryProvider(apps: [
            InstalledApp(bundleIdentifier: "com.example.source", displayName: "Source", isSystemApp: false),
            InstalledApp(bundleIdentifier: "com.example.target", displayName: "Target", isSystemApp: false)
        ])
        let result = try await ReadOnlyPluginAssociationReader(appDiscoveryProvider: provider)
            .readAssociations(from: scan)
        XCTAssertTrue(result.snapshots.isEmpty)
        XCTAssertEqual(result.skippedPluginIDs, ["Example.dylib"])
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


    func testReinstallingFixedOwnerRestoresAvailabilityWithoutChangingIdentity() async throws {
        let pluginID = UUID()
        let scan = makeScan(pluginID: pluginID, hardBound: "com.example.source", soft: ["com.example.secondary"])

        let missingResult = try await ReadOnlyPluginAssociationReader(
            appDiscoveryProvider: StubAppDiscoveryProvider(apps: [
                InstalledApp(bundleIdentifier: "com.example.secondary", displayName: "Secondary", isSystemApp: false)
            ])).readAssociations(from: scan)
        let missing = try XCTUnwrap(missingResult.snapshots.first)
        XCTAssertEqual(missing.availability(for: "com.example.source"), .unavailable)
        XCTAssertEqual(missing.availability(for: "com.example.secondary"), .available)
        XCTAssertNil(missing.availability(for: "com.example.unrelated"))
        XCTAssertTrue(missing.hasAnyAvailableAssociation)
        XCTAssertEqual(missing.hardBoundBundleIdentifier, "com.example.source")

        let reinstalledResult = try await ReadOnlyPluginAssociationReader(
            appDiscoveryProvider: StubAppDiscoveryProvider(apps: [
                InstalledApp(bundleIdentifier: "com.example.source", displayName: "Source Reinstalled", isSystemApp: false),
                InstalledApp(bundleIdentifier: "com.example.secondary", displayName: "Secondary", isSystemApp: false)
            ])).readAssociations(from: scan)
        let reinstalled = try XCTUnwrap(reinstalledResult.snapshots.first)
        XCTAssertEqual(reinstalled.availability(for: "com.example.source"), .available)
        XCTAssertEqual(reinstalled.hardBoundBundleIdentifier, "com.example.source")
        XCTAssertEqual(reinstalled.pluginID, pluginID)
    }

    func testReinstallingSoftAssociatedAppRestoresAvailabilityWithoutCreatingNewAssociation() async throws {
        let pluginID = UUID()
        let scan = makeScan(pluginID: pluginID, hardBound: "com.example.source", soft: ["com.example.secondary"])
        let missing = try await ReadOnlyPluginAssociationReader(
            appDiscoveryProvider: StubAppDiscoveryProvider(apps: [
                InstalledApp(bundleIdentifier: "com.example.source", displayName: "Source", isSystemApp: false)
            ])).readAssociations(from: scan)
        let missingSnapshot = try XCTUnwrap(missing.snapshots.first)
        XCTAssertEqual(missingSnapshot.availability(for: "com.example.secondary"), .unavailable)

        let restored = try await ReadOnlyPluginAssociationReader(
            appDiscoveryProvider: StubAppDiscoveryProvider(apps: [
                InstalledApp(bundleIdentifier: "com.example.source", displayName: "Source", isSystemApp: false),
                InstalledApp(bundleIdentifier: "com.example.secondary", displayName: "Secondary Reinstalled", isSystemApp: false)
            ])).readAssociations(from: scan)
        let restoredSnapshot = try XCTUnwrap(restored.snapshots.first)
        XCTAssertEqual(restoredSnapshot.availability(for: "com.example.secondary"), .available)
        XCTAssertEqual(restoredSnapshot.effectiveBundleIdentifiers, ["com.example.secondary", "com.example.source"])
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
