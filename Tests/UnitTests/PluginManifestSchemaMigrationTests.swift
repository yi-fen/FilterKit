import XCTest
@testable import FilterKit

final class PluginManifestSchemaMigrationTests: XCTestCase {
    private let pluginID = UUID().uuidString
    private let hash = String(repeating: "a", count: 64)

    func testCreatesAndEncodesSchemaThreeWithExplicitState() throws {
        let plan = PluginAssociationPlan(pluginID: UUID(uuidString: pluginID)!,
            hardBoundBundleIdentifier: "com.example.source",
            softAssociations: [PluginSoftAssociation(bundleIdentifier: "com.example.secondary", isEnabled: false)])
        let migrator = PluginManifestSchemaMigrator()
        let manifest = try migrator.makeSchemaThreeManifest(pluginID: plan.pluginID,
            dylibFileName: "Demo.dylib", plistFileName: "Demo.plist",
            dylibSHA256: hash, plistSHA256: hash, machOIdentitySHA256: hash,
            associationPlan: plan)
        let data = try migrator.encodeSchemaThreeManifest(manifest)
        let decoded = try JSONDecoder().decode(FilterKitPluginManifest.self, from: data)
        XCTAssertEqual(decoded.schemaVersion, 3)
        XCTAssertEqual(decoded.softAssociations?.first?.isEnabled, false)
    }

    func testSchemaOneMigratesWithLegacyAssociationsEnabledAndNoWrite() throws {
        let data = try manifestJSON(schema: 1, softIDs: ["com.example.secondary"])
        let preview = try PluginManifestSchemaMigrator().decodeAndPreviewUpgrade(data, actualDylibSHA256: hash, actualPlistSHA256: hash, machOIdentitySHA256: hash)
        XCTAssertEqual(preview.sourceSchemaVersion, 1)
        XCTAssertEqual(preview.targetSchemaVersion, 3)
        XCTAssertTrue(preview.requiresBinaryIdentityVerification)
        XCTAssertFalse(preview.writesToDisk)
        XCTAssertEqual(preview.migratedManifest.softAssociations, [
            FilterKitManifestSoftAssociation(bundleIdentifier: "com.example.secondary", isEnabled: true)
        ])
        XCTAssertTrue(preview.warnings.contains("legacy_soft_associations_interpreted_as_enabled"))
    }

    func testSchemaTwoMigratesAndKeepsLegacyEnabledInterpretation() throws {
        let data = try manifestJSON(schema: 2, softIDs: ["com.example.secondary"])
        let preview = try PluginManifestSchemaMigrator().decodeAndPreviewUpgrade(data, actualDylibSHA256: hash, actualPlistSHA256: hash, machOIdentitySHA256: hash)
        XCTAssertFalse(preview.requiresBinaryIdentityVerification)
        XCTAssertEqual(preview.migratedManifest.softAssociations?.first?.isEnabled, true)
    }

    func testSchemaThreePreservesDisabledAssociation() throws {
        let object: [String: Any] = [
            "schemaVersion": 3, "pluginID": pluginID,
            "dylibFileName": "Demo.dylib", "plistFileName": "Demo.plist",
            "dylibSHA256": hash, "plistSHA256": hash,
            "hardBoundBundleIdentifier": "com.example.source",
            "softAssociatedBundleIdentifiers": ["com.example.secondary"],
            "machOIdentitySHA256": hash,
            "softAssociations": [["bundleIdentifier": "com.example.secondary", "isEnabled": false]]
        ]
        let data = try JSONSerialization.data(withJSONObject: object)
        let preview = try PluginManifestSchemaMigrator().decodeAndPreviewUpgrade(data, actualDylibSHA256: hash, actualPlistSHA256: hash, machOIdentitySHA256: hash)
        XCTAssertEqual(preview.migratedManifest.softAssociations?.first?.isEnabled, false)
    }

    func testRejectsSchemaThreeStateMismatch() throws {
        let object: [String: Any] = [
            "schemaVersion": 3, "pluginID": pluginID,
            "dylibFileName": "Demo.dylib", "plistFileName": "Demo.plist",
            "dylibSHA256": hash, "plistSHA256": hash,
            "hardBoundBundleIdentifier": "com.example.source",
            "softAssociatedBundleIdentifiers": ["com.example.secondary"],
            "machOIdentitySHA256": hash,
            "softAssociations": [["bundleIdentifier": "com.example.secondary", "isEnabled": false],
                                 ["bundleIdentifier": "com.example.secondary", "isEnabled": true]]
        ]
        let data = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(try PluginManifestSchemaMigrator().decodeAndPreviewUpgrade(data, actualDylibSHA256: hash, actualPlistSHA256: hash, machOIdentitySHA256: hash))
    }

    func testRejectsChangedBinaryIdentityAndFileHashes() throws {
        let schemaTwo = try manifestJSON(schema: 2, softIDs: [])
        XCTAssertThrowsError(try PluginManifestSchemaMigrator().decodeAndPreviewUpgrade(
            schemaTwo, actualDylibSHA256: hash, actualPlistSHA256: hash,
            machOIdentitySHA256: String(repeating: "b", count: 64)))
        XCTAssertThrowsError(try PluginManifestSchemaMigrator().decodeAndPreviewUpgrade(
            schemaTwo, actualDylibSHA256: String(repeating: "b", count: 64),
            actualPlistSHA256: hash, machOIdentitySHA256: hash))
    }

    func testRejectsMissingIdentityAndUnsafeFilename() throws {
        let data = try manifestJSON(schema: 2, softIDs: [])
        XCTAssertThrowsError(try PluginManifestSchemaMigrator().decodeAndPreviewUpgrade(data, actualDylibSHA256: hash, actualPlistSHA256: hash, machOIdentitySHA256: nil))
        let unsafe = try manifestJSON(schema: 2, softIDs: [], dylibName: "../Demo.dylib")
        XCTAssertThrowsError(try PluginManifestSchemaMigrator().decodeAndPreviewUpgrade(unsafe, actualDylibSHA256: hash, actualPlistSHA256: hash, machOIdentitySHA256: hash))
    }

    private func manifestJSON(schema: Int, softIDs: [String], dylibName: String = "Demo.dylib") throws -> Data {
        let object: [String: Any] = [
            "schemaVersion": schema, "pluginID": pluginID,
            "dylibFileName": dylibName, "plistFileName": "Demo.plist",
            "dylibSHA256": hash, "plistSHA256": hash,
            "hardBoundBundleIdentifier": "com.example.source",
            "softAssociatedBundleIdentifiers": softIDs,
            "machOIdentitySHA256": hash
        ]
        return try JSONSerialization.data(withJSONObject: object)
    }
}
