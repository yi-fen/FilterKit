import XCTest
@testable import FilterKit

final class FilterKitBackupCodecTests: XCTestCase {
    private let dylib = Data([0x4d, 0x5a, 0x01, 0x02])
    private let plist = Data("<?xml version=\"1.0\"?><plist version=\"1.0\"><dict/></plist>".utf8)

    private func entry(schema: Int = 2) -> BackupPluginEntry {
        let dylib = self.dylib, plist = self.plist
        return BackupPluginEntry(pluginIdentifier: UUID(), dylibFileName: "Demo.dylib",
            dylibDataBase64: dylib.base64EncodedString(), dylibSHA256: SHA256Digest.hex(dylib),
            plistFileName: "Demo.plist", plistDataBase64: plist.base64EncodedString(), plistSHA256: SHA256Digest.hex(plist),
            hardBoundBundleIdentifier: "com.example.main", softAssociatedBundleIdentifiers: ["com.example.secondary"],
            softAssociations: schema == 2 ? [FilterKitManifestSoftAssociation(bundleIdentifier: "com.example.secondary", isEnabled: false)] : nil)
    }

    func testSchemaTwoRoundTripPreservesPayloadAndDisabledAssociation() throws {
        let document = FilterKitBackupDocument(plugins: [entry()])
        let codec = FilterKitBackupCodec()
        let encoded = try codec.encode(document)
        let decoded = try codec.decodeAndValidate(encoded)
        XCTAssertEqual(decoded.plugins.first?.dylibData, dylib)
        XCTAssertEqual(decoded.plugins.first?.plistData, plist)
        XCTAssertEqual(decoded.plugins.first?.associationPlan.softAssociations.first?.isEnabled, false)
    }

    func testSchemaOneLegacyAssociationsDefaultEnabled() throws {
        let validated = try FilterKitBackupCodec().validate(FilterKitBackupDocument(schemaVersion: 1, plugins: [entry(schema: 1)]))
        XCTAssertEqual(validated.first?.associationPlan.softAssociations.first?.isEnabled, true)
    }

    func testRejectsHashMismatchAndTraversalPath() throws {
        let good = entry()
        let badHash = BackupPluginEntry(pluginIdentifier: good.pluginIdentifier, dylibFileName: good.dylibFileName,
            dylibDataBase64: good.dylibDataBase64, dylibSHA256: String(repeating: "0", count: 64),
            plistFileName: good.plistFileName, plistDataBase64: good.plistDataBase64, plistSHA256: good.plistSHA256,
            hardBoundBundleIdentifier: good.hardBoundBundleIdentifier, softAssociatedBundleIdentifiers: good.softAssociatedBundleIdentifiers,
            softAssociations: good.softAssociations)
        XCTAssertThrowsError(try FilterKitBackupCodec().validate(FilterKitBackupDocument(plugins: [badHash])))
        let unsafe = BackupPluginEntry(pluginIdentifier: good.pluginIdentifier, dylibFileName: "../Demo.dylib",
            dylibDataBase64: good.dylibDataBase64, dylibSHA256: good.dylibSHA256, plistFileName: good.plistFileName,
            plistDataBase64: good.plistDataBase64, plistSHA256: good.plistSHA256,
            hardBoundBundleIdentifier: good.hardBoundBundleIdentifier, softAssociatedBundleIdentifiers: good.softAssociatedBundleIdentifiers,
            softAssociations: good.softAssociations)
        XCTAssertThrowsError(try FilterKitBackupCodec().validate(FilterKitBackupDocument(plugins: [unsafe])))
    }

    func testRestorePreviewSeparatesMissingAppsAndFileConflicts() throws {
        let validated = try FilterKitBackupCodec().validate(FilterKitBackupDocument(plugins: [entry()]))
        let preview = BackupRestorePreviewBuilder().build(validated: validated,
            installedBundleIdentifiers: ["com.example.main"], existingFileNames: ["Demo.dylib"])
        XCTAssertEqual(preview.plugins.first?.disposition, .fileConflict)
        XCTAssertEqual(preview.plugins.first?.missingBundleIdentifiers, ["com.example.secondary"])
    }
}
