import XCTest
@testable import FilterKit

final class FilterKitBackupCodecTests: XCTestCase {
    private let dylib = Data([0x4d, 0x5a, 0x01, 0x02])
    private let plist = Data("<?xml version=\"1.0\"?><plist version=\"1.0\"><dict/></plist>".utf8)

    private func entry(schema: Int = 3, fixedOwner: String? = "com.example.main") -> BackupPluginEntry {
        let dylib = self.dylib, plist = self.plist
        let states = [FilterKitManifestSoftAssociation(bundleIdentifier: "com.example.secondary", isEnabled: false)]
        let topology = FilterKitManifestBindingTopology(schemaVersion: 1,
            fixedOwnerBundleIdentifier: fixedOwner, fixedOwnerIsEnabled: false,
            additionalAssociations: states)
        let pluginID = UUID()
        let manifest: Data? = schema >= 3 ? try? JSONEncoder().encode(FilterKitPluginManifest(
            schemaVersion: 4, pluginID: pluginID.uuidString,
            dylibFileName: "Demo.dylib", plistFileName: "Demo.plist",
            dylibSHA256: SHA256Digest.hex(dylib), plistSHA256: SHA256Digest.hex(plist),
            hardBoundBundleIdentifier: fixedOwner,
            softAssociatedBundleIdentifiers: ["com.example.secondary"],
            machOIdentitySHA256: nil, softAssociations: states, bindingTopology: topology)) : nil
        return BackupPluginEntry(pluginIdentifier: pluginID, dylibFileName: "Demo.dylib",
            dylibDataBase64: dylib.base64EncodedString(), dylibSHA256: SHA256Digest.hex(dylib),
            plistFileName: "Demo.plist", plistDataBase64: plist.base64EncodedString(), plistSHA256: SHA256Digest.hex(plist),
            hardBoundBundleIdentifier: fixedOwner,
            softAssociatedBundleIdentifiers: ["com.example.secondary"],
            softAssociations: schema >= 2 ? states : nil,
            bindingTopology: schema >= 3 ? topology : nil,
            manifestDataBase64: manifest?.base64EncodedString(),
            manifestSHA256: manifest.map(SHA256Digest.hex))
    }

    func testSchemaTwoRoundTripPreservesPayloadAndDisabledAssociation() throws {
        let document = FilterKitBackupDocument(schemaVersion: 2, plugins: [entry(schema: 2)])
        let codec = FilterKitBackupCodec()
        let encoded = try codec.encode(document)
        let decoded = try codec.decodeAndValidate(encoded)
        XCTAssertEqual(decoded.plugins.first?.dylibData, dylib)
        XCTAssertEqual(decoded.plugins.first?.plistData, plist)
        XCTAssertEqual(decoded.plugins.first?.bindingTopology.additionalAssociations.first?.isEnabled, false)
    }

    func testSchemaOneLegacyAssociationsDefaultEnabled() throws {
        let validated = try FilterKitBackupCodec().validate(FilterKitBackupDocument(schemaVersion: 1, plugins: [entry(schema: 1)]))
        XCTAssertEqual(validated.first?.associationPlan?.softAssociations.first?.isEnabled, true)
    }

    func testRejectsHashMismatchAndTraversalPath() throws {
        let good = entry()
        let badHash = BackupPluginEntry(pluginIdentifier: good.pluginIdentifier, dylibFileName: good.dylibFileName,
            dylibDataBase64: good.dylibDataBase64, dylibSHA256: String(repeating: "0", count: 64),
            plistFileName: good.plistFileName, plistDataBase64: good.plistDataBase64, plistSHA256: good.plistSHA256,
            hardBoundBundleIdentifier: good.hardBoundBundleIdentifier, softAssociatedBundleIdentifiers: good.softAssociatedBundleIdentifiers,
            softAssociations: good.softAssociations)
        XCTAssertThrowsError(try FilterKitBackupCodec().validate(FilterKitBackupDocument(schemaVersion: 2, plugins: [badHash])))
        let unsafe = BackupPluginEntry(pluginIdentifier: good.pluginIdentifier, dylibFileName: "../Demo.dylib",
            dylibDataBase64: good.dylibDataBase64, dylibSHA256: good.dylibSHA256, plistFileName: good.plistFileName,
            plistDataBase64: good.plistDataBase64, plistSHA256: good.plistSHA256,
            hardBoundBundleIdentifier: good.hardBoundBundleIdentifier, softAssociatedBundleIdentifiers: good.softAssociatedBundleIdentifiers,
            softAssociations: good.softAssociations)
        XCTAssertThrowsError(try FilterKitBackupCodec().validate(FilterKitBackupDocument(schemaVersion: 2, plugins: [unsafe])))
    }

    func testSchemaThreeSupportsAdditionalAssociationsOnlyAndPreservesOwnerState() throws {
        let pureAdditional = entry(fixedOwner: nil)
        let fixedOwnerDisabled = entry(fixedOwner: "com.example.main")
        let codec = FilterKitBackupCodec()
        let decoded = try codec.decodeAndValidate(try codec.encode(FilterKitBackupDocument(plugins: [pureAdditional, fixedOwnerDisabled])))
        XCTAssertNil(decoded.plugins[0].bindingTopology.fixedOwnerBundleIdentifier)
        XCTAssertEqual(decoded.plugins[0].bindingTopology.additionalAssociations.first?.isEnabled, false)
        XCTAssertEqual(decoded.plugins[1].bindingTopology.fixedOwnerBundleIdentifier, "com.example.main")
        XCTAssertFalse(decoded.plugins[1].bindingTopology.fixedOwnerIsEnabled)
    }

    func testSchemaThreeRejectsEmptyTopology() throws {
        let empty = BackupPluginEntry(pluginIdentifier: UUID(), dylibFileName: "Demo.dylib",
            dylibDataBase64: dylib.base64EncodedString(), dylibSHA256: SHA256Digest.hex(dylib),
            plistFileName: "Demo.plist", plistDataBase64: plist.base64EncodedString(), plistSHA256: SHA256Digest.hex(plist),
            hardBoundBundleIdentifier: nil, softAssociatedBundleIdentifiers: [], softAssociations: [],
            bindingTopology: FilterKitManifestBindingTopology(schemaVersion: 1,
                fixedOwnerBundleIdentifier: nil, fixedOwnerIsEnabled: true, additionalAssociations: []))
        XCTAssertThrowsError(try FilterKitBackupCodec().validate(FilterKitBackupDocument(plugins: [empty])))
    }


    func testSchemaThreeAcceptsCaseVariantBundleIdentityMirrors() throws {
        let base = entry()
        let owner = "COM.EXAMPLE.MAIN"
        let association = FilterKitManifestSoftAssociation(bundleIdentifier: "COM.EXAMPLE.SECONDARY", isEnabled: false)
        let topology = FilterKitManifestBindingTopology(schemaVersion: 1,
            fixedOwnerBundleIdentifier: owner, fixedOwnerIsEnabled: false,
            additionalAssociations: [association])
        let manifest = FilterKitPluginManifest(schemaVersion: 4, pluginID: base.pluginIdentifier.uuidString,
            dylibFileName: base.dylibFileName, plistFileName: base.plistFileName,
            dylibSHA256: base.dylibSHA256, plistSHA256: base.plistSHA256,
            hardBoundBundleIdentifier: owner, softAssociatedBundleIdentifiers: [association.bundleIdentifier],
            machOIdentitySHA256: nil, softAssociations: [association], bindingTopology: topology)
        let manifestData = try JSONEncoder().encode(manifest)
        let mixedCase = BackupPluginEntry(pluginIdentifier: base.pluginIdentifier,
            dylibFileName: base.dylibFileName, dylibDataBase64: base.dylibDataBase64,
            dylibSHA256: base.dylibSHA256, plistFileName: base.plistFileName,
            plistDataBase64: base.plistDataBase64, plistSHA256: base.plistSHA256,
            hardBoundBundleIdentifier: "com.example.main",
            softAssociatedBundleIdentifiers: ["com.example.secondary"],
            softAssociations: [FilterKitManifestSoftAssociation(bundleIdentifier: "com.example.secondary", isEnabled: false)],
            bindingTopology: FilterKitManifestBindingTopology(schemaVersion: 1,
                fixedOwnerBundleIdentifier: "com.example.main", fixedOwnerIsEnabled: false,
                additionalAssociations: [FilterKitManifestSoftAssociation(bundleIdentifier: "com.example.secondary", isEnabled: false)]),
            manifestDataBase64: manifestData.base64EncodedString(), manifestSHA256: SHA256Digest.hex(manifestData))

        XCTAssertNoThrow(try FilterKitBackupCodec().validate(FilterKitBackupDocument(plugins: [mixedCase])))
    }

    func testSchemaThreeRejectsCaseVariantDuplicateAssociations() throws {
        let base = entry()
        let duplicateStates = [
            FilterKitManifestSoftAssociation(bundleIdentifier: "com.example.secondary", isEnabled: false),
            FilterKitManifestSoftAssociation(bundleIdentifier: "COM.EXAMPLE.SECONDARY", isEnabled: false)
        ]
        let topology = FilterKitManifestBindingTopology(schemaVersion: 1,
            fixedOwnerBundleIdentifier: "com.example.main", fixedOwnerIsEnabled: true,
            additionalAssociations: duplicateStates)
        let invalid = BackupPluginEntry(pluginIdentifier: base.pluginIdentifier,
            dylibFileName: base.dylibFileName, dylibDataBase64: base.dylibDataBase64,
            dylibSHA256: base.dylibSHA256, plistFileName: base.plistFileName,
            plistDataBase64: base.plistDataBase64, plistSHA256: base.plistSHA256,
            hardBoundBundleIdentifier: "com.example.main",
            softAssociatedBundleIdentifiers: duplicateStates.map(\.bundleIdentifier),
            softAssociations: duplicateStates, bindingTopology: topology,
            manifestDataBase64: base.manifestDataBase64, manifestSHA256: base.manifestSHA256)
        XCTAssertThrowsError(try FilterKitBackupCodec().validate(FilterKitBackupDocument(plugins: [invalid])))
    }

    func testRestorePreviewMatchesInstalledAppsCaseInsensitively() throws {
        let validated = try FilterKitBackupCodec().validate(FilterKitBackupDocument(plugins: [entry()]))
        let preview = BackupRestorePreviewBuilder().build(validated: validated,
            installedBundleIdentifiers: ["COM.EXAMPLE.MAIN"])
        XCTAssertEqual(preview.plugins.first?.disposition, .softAppsMissing)
        XCTAssertEqual(preview.plugins.first?.missingBundleIdentifiers, ["com.example.secondary"])
    }

    func testRestorePreviewSeparatesMissingAppsAndFileConflicts() throws {
        let validated = try FilterKitBackupCodec().validate(FilterKitBackupDocument(plugins: [entry()]))
        let preview = BackupRestorePreviewBuilder().build(validated: validated,
            installedBundleIdentifiers: ["com.example.main"], existingFileNames: ["Demo.dylib"])
        XCTAssertEqual(preview.plugins.first?.disposition, .fileConflict)
        XCTAssertEqual(preview.plugins.first?.missingBundleIdentifiers, ["com.example.secondary"])
    }
}
    func testRestoreDefaultsToSkippingPluginsWithoutInstalledAssociations() throws {
        let validated = try FilterKitBackupCodec().validate(FilterKitBackupDocument(plugins: [entry()]))
        let preview = BackupRestorePreviewBuilder().build(validated: validated,
            installedBundleIdentifiers: [])
        XCTAssertEqual(preview.plugins.first?.disposition, .skippedNoInstalledAssociation)
        XCTAssertEqual(preview.skippedCount, 1)
        XCTAssertEqual(preview.readyCount, 0)
    }

    func testRestoreAcceptsInstalledAdditionalAssociationWhenFixedOwnerIsMissing() throws {
        let validated = try FilterKitBackupCodec().validate(FilterKitBackupDocument(plugins: [entry()]))
        let preview = BackupRestorePreviewBuilder().build(validated: validated,
            installedBundleIdentifiers: ["com.example.secondary"])
        XCTAssertEqual(preview.plugins.first?.disposition, .softAppsMissing)
        XCTAssertEqual(preview.plugins.first?.missingBundleIdentifiers, ["com.example.main"])
        XCTAssertEqual(preview.readyCount, 1)
    }

    func testRestoreSkipsExactPackageManagedSHA256Duplicate() throws {
        let validated = try FilterKitBackupCodec().validate(FilterKitBackupDocument(plugins: [entry()]))
        let hash = validated[0].entry.dylibSHA256
        let preview = BackupRestorePreviewBuilder().build(validated: validated,
            installedBundleIdentifiers: ["com.example.main"],
            packageManagedDylibSHA256s: [hash])
        XCTAssertEqual(preview.plugins.first?.disposition, .externalDuplicate)
        XCTAssertEqual(preview.skippedCount, 1)
    }

    func testRestoreCanDisableInstalledAppFiltering() throws {
        let validated = try FilterKitBackupCodec().validate(FilterKitBackupDocument(plugins: [entry()]))
        let preview = BackupRestorePreviewBuilder().build(validated: validated,
            installedBundleIdentifiers: [], filterToInstalledApps: false)
        XCTAssertEqual(preview.plugins.first?.disposition, .softAppsMissing)
        XCTAssertEqual(preview.readyCount, 1)
    }

