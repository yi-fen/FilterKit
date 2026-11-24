import XCTest
@testable import FilterKit

final class BackupAssociationCompatibilityTests: XCTestCase {
    func testLegacyBackupAssociationsDefaultToEnabled() throws {
        let entry = makeEntry(states: nil)
        let plan = try BackupAssociationCompatibility().resolvedPlan(from: entry, backupSchemaVersion: entry.softAssociations == nil ? 1 : 2)
        XCTAssertEqual(plan.softAssociations, [
            PluginSoftAssociation(bundleIdentifier: "com.example.secondary", isEnabled: true)
        ])
    }

    func testNewBackupPreservesDisabledState() throws {
        let entry = makeEntry(states: [
            FilterKitManifestSoftAssociation(bundleIdentifier: "com.example.secondary", isEnabled: false)
        ])
        let plan = try BackupAssociationCompatibility().resolvedPlan(from: entry, backupSchemaVersion: entry.softAssociations == nil ? 1 : 2)
        XCTAssertEqual(plan.softAssociations.first?.isEnabled, false)
    }

    func testBackupRejectsHardBoundAsSoftAssociation() {
        let entry = makeEntry(states: [
            FilterKitManifestSoftAssociation(bundleIdentifier: "com.example.source", isEnabled: true)
        ])
        XCTAssertThrowsError(try BackupAssociationCompatibility().resolvedPlan(from: entry, backupSchemaVersion: entry.softAssociations == nil ? 1 : 2))
    }

    private func makeEntry(states: [FilterKitManifestSoftAssociation]?) -> BackupPluginEntry {
        BackupPluginEntry(pluginIdentifier: UUID(), dylibFileName: "Demo.dylib", dylibDataBase64: "AA==",
            dylibSHA256: String(repeating: "a", count: 64), plistFileName: "Demo.plist", plistDataBase64: "AA==",
            plistSHA256: String(repeating: "b", count: 64), hardBoundBundleIdentifier: "com.example.source",
            softAssociatedBundleIdentifiers: ["com.example.secondary"], softAssociations: states)
    }
}
