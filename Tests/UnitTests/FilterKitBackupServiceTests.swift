import XCTest
@testable import FilterKit

final class FilterKitBackupServiceTests: XCTestCase {
    func testExportsOnlyVerifiedFilterKitOwnedPluginAndPreservesBytes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let pluginDirectory = root.appendingPathComponent("ElleKit", isDirectory: true)
        try FileManager.default.createDirectory(at: pluginDirectory, withIntermediateDirectories: true)
        let pluginID = UUID()
        let dylib = Data([0xca, 0xfe, 0xba, 0xbe, 1, 2, 3])
        let plist = try PropertyListSerialization.data(fromPropertyList: ["Filter": ["Bundles": ["com.example.source"]]], format: .xml, options: 0)
        let dylibName = "Example.dylib"
        let plistName = "Example.plist"
        let manifestName = "Example.fk.json"
        let dylibHash = SHA256Digest.hex(dylib)
        let plistHash = SHA256Digest.hex(plist)
        let association = FilterKitManifestSoftAssociation(bundleIdentifier: "com.example.secondary", isEnabled: false)
        let identity = PluginIdentityAnalyzer.fingerprint(installNames: ["@rpath/Example.dylib"],
            uuids: ["11111111-2222-3333-4444-555555555555"],
            cdHashes: ["0123456789abcdef"], architectures: ["arm64"] )!
        let manifest = FilterKitPluginManifest(schemaVersion: 3, pluginID: pluginID.uuidString,
            dylibFileName: dylibName, plistFileName: plistName,
            dylibSHA256: dylibHash, plistSHA256: plistHash,
            hardBoundBundleIdentifier: "com.example.source",
            softAssociatedBundleIdentifiers: [association.bundleIdentifier],
            machOIdentitySHA256: identity, softAssociations: [association])
        let manifestData = try JSONEncoder().encode(manifest)
        try dylib.write(to: pluginDirectory.appendingPathComponent(dylibName))
        try plist.write(to: pluginDirectory.appendingPathComponent(plistName))
        try manifestData.write(to: pluginDirectory.appendingPathComponent(manifestName))

        let item = PluginScanItem(id: "Example.dylib", baseName: "Example",
            dylibFileName: dylibName, plistFileName: plistName, manifestFileName: manifestName,
            pairingState: .paired, binaryKind: .machO, ownership: .filterKit,
            filterKitPluginID: pluginID.uuidString, packageIdentifier: nil,
            dylibSHA256: dylibHash, plistSHA256: plistHash,
            hardBoundBundleIdentifier: "com.example.source",
            softAssociatedBundleIdentifiers: [association.bundleIdentifier], warnings: [],
            filterConfiguration: PluginFilterConfiguration.parse(plist),
            managementPermission: PluginManagementPermission(access: .manageable, reasonKey: "test"),
            machOInstallName: "@rpath/Example.dylib", machOUUIDs: ["11111111-2222-3333-4444-555555555555"],
            machOArchitectures: ["arm64"], machOCDHashes: ["0123456789abcdef"],
            identityFingerprint: identity, identityStatus: .unique,
            softAssociationStates: [association],
            dylibPath: pluginDirectory.appendingPathComponent(dylibName).path,
            plistPath: pluginDirectory.appendingPathComponent(plistName).path,
            manifestPath: pluginDirectory.appendingPathComponent(manifestName).path)
        let scan = PluginScanResult(scannedAt: Date(), scannedDirectory: root.path,
            directoryState: .resolved, plugins: [item], issues: [], isReadOnly: true,
            scannedDirectories: [root.path, pluginDirectory.path])

        let archive = try FilterKitBackupService().makeBackup(scan: scan, pluginIDs: [pluginID])
        let decoded = try FilterKitBackupCodec().decodeAndValidate(archive)
        XCTAssertEqual(decoded.plugins.count, 1)
        XCTAssertEqual(decoded.plugins[0].dylibData, dylib)
        XCTAssertEqual(decoded.plugins[0].plistData, plist)
        XCTAssertEqual(decoded.plugins[0].associationPlan.softAssociations.first?.isEnabled, false)
        XCTAssertEqual(decoded.plugins[0].manifestData, manifestData)
    }

    func testRejectsNonFilterKitOwnership() throws {
        let id = UUID()
        let item = PluginScanItem(id: "Example.dylib", baseName: "Example",
            dylibFileName: "Example.dylib", plistFileName: "Example.plist", manifestFileName: "Example.fk.json",
            pairingState: .paired, binaryKind: .machO, ownership: .packageManager,
            filterKitPluginID: id.uuidString, packageIdentifier: "com.example.package",
            dylibSHA256: String(repeating: "a", count: 64), plistSHA256: String(repeating: "b", count: 64),
            hardBoundBundleIdentifier: "com.example.source", softAssociatedBundleIdentifiers: [], warnings: [],
            filterConfiguration: nil,
            managementPermission: PluginManagementPermission(access: .readOnlyPackageManager, reasonKey: "test"))
        let scan = PluginScanResult(scannedAt: Date(), scannedDirectory: NSTemporaryDirectory(),
            directoryState: .resolved, plugins: [item], issues: [], isReadOnly: true)
        XCTAssertThrowsError(try FilterKitBackupService().makeBackup(scan: scan, pluginIDs: [id]))
    }
}
