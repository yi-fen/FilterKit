import XCTest
@testable import FilterKit
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

final class HelperPluginFilterConfigurationTransactionTests: XCTestCase {
    func testCrashAfterFirstRenameRestoresBothOriginalFiles() throws {
        guard geteuid() == 0 else { throw XCTSkip("Root-only transaction test") }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fk-assoc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)

        let pluginID = UUID(), dylib = "Example.dylib", plistName = "Example.plist", manifestName = "Example.fk.json"
        let oldPlist = try PropertyListSerialization.data(fromPropertyList: ["Filter": ["Bundles": ["com.example.host"]]], format: .xml, options: 0)
        let newPlist = try PropertyListSerialization.data(fromPropertyList: ["Filter": ["Bundles": ["com.example.host", "com.example.target"]]], format: .xml, options: 0)
        let dylibHash = String(repeating: "c", count: 64), oldPlistHash = SHA256Digest.hex(oldPlist), newPlistHash = SHA256Digest.hex(newPlist)
        func manifest(_ plistHash: String) throws -> Data {
            let value = FilterKitPluginManifest(schemaVersion: 3, pluginID: pluginID.uuidString, dylibFileName: dylib,
                plistFileName: plistName, dylibSHA256: dylibHash, plistSHA256: plistHash,
                hardBoundBundleIdentifier: "com.example.host", softAssociatedBundleIdentifiers: ["com.example.target"],
                machOIdentitySHA256: String(repeating: "d", count: 64),
                softAssociations: [FilterKitManifestSoftAssociation(bundleIdentifier: "com.example.target", isEnabled: false)])
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            return try encoder.encode(value)
        }
        let oldManifest = try manifest(oldPlistHash), newManifest = try manifest(newPlistHash)
        try oldPlist.write(to: dir.appendingPathComponent(plistName))
        try oldManifest.write(to: dir.appendingPathComponent(manifestName))
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: dir.appendingPathComponent(plistName).path)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dir.appendingPathComponent(manifestName).path)
        let request = HelperPluginFilterMutationRequest(requestID: UUID(), pluginID: pluginID, action: .enableForApp,
            dylibFileName: dylib, plistFileName: plistName, targetBundleIdentifier: "com.example.target",
            expectedPlistSHA256: oldPlistHash, expectedManifestSHA256: SHA256Digest.hex(oldManifest), createdAt: Date())
        let proof = try HelperOwnershipProof(pluginID: pluginID, dylibFileName: dylib, plistFileName: plistName,
            dylibSHA256: dylibHash, plistSHA256: oldPlistHash, manifestSchemaVersion: 3,
            manifestSHA256: SHA256Digest.hex(oldManifest), binaryIdentityVerified: true)
        let prepared = HelperPluginFilterMutationAuthorizer.PreparedMutation(request: request, ownershipProof: proof,
            previousPlistData: oldPlist, replacementPlistData: newPlist, previousManifestData: oldManifest,
            replacementManifestData: newManifest, disposition: .preparedForAtomicCommit)
        let transaction = try HelperPluginFilterConfigurationTransaction(directoryPath: dir.path)
        XCTAssertThrowsError(try transaction.execute(prepared, simulateCrashAfter: .replacingManifest))
        XCTAssertTrue(try transaction.inspectPendingJournal())
        XCTAssertTrue(try transaction.reconcile())
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent(plistName)), oldPlist)
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent(manifestName)), oldManifest)
        XCTAssertFalse(try transaction.inspectPendingJournal())
    }
}
