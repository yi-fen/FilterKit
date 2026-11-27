import XCTest
@testable import FilterKit
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

final class HelperPluginFilterConfigurationTransactionTests: XCTestCase {
    private struct Fixture {
        let directory: URL
        let pluginID: UUID
        let plistName: String
        let manifestName: String
        let oldPlist: Data
        let newPlist: Data
        let oldManifest: Data
        let newManifest: Data
        let prepared: HelperPluginFilterMutationAuthorizer.PreparedMutation
        let transaction: HelperPluginFilterConfigurationTransaction
    }

    private func makeFixture() throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("fk-assoc-r2-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)

        let pluginID = UUID()
        let dylibName = "Example.dylib"
        let plistName = "Example.plist"
        let manifestName = "Example.fk.json"
        let plist = try PropertyListSerialization.data(
            fromPropertyList: ["Filter": ["Bundles": ["com.example.host"]]],
            format: .xml, options: 0)
        let plistHash = SHA256Digest.hex(plist)
        let dylibHash = String(repeating: "c", count: 64)
        let identityHash = String(repeating: "d", count: 64)

        func manifest(_ associations: [FilterKitManifestSoftAssociation]) throws -> Data {
            let value = FilterKitPluginManifest(schemaVersion: 3,
                pluginID: pluginID.uuidString, dylibFileName: dylibName,
                plistFileName: plistName, dylibSHA256: dylibHash,
                plistSHA256: plistHash, hardBoundBundleIdentifier: "com.example.host",
                softAssociatedBundleIdentifiers: associations.map(\.bundleIdentifier),
                machOIdentitySHA256: identityHash, softAssociations: associations)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            return try encoder.encode(value)
        }

        let oldAssociations = [FilterKitManifestSoftAssociation(
            bundleIdentifier: "com.example.target", isEnabled: false)]
        let newAssociations = oldAssociations + [FilterKitManifestSoftAssociation(
            bundleIdentifier: "com.example.second", isEnabled: false)]
        let oldManifest = try manifest(oldAssociations)
        let newManifest = try manifest(newAssociations)
        try plist.write(to: directory.appendingPathComponent(plistName))
        try oldManifest.write(to: directory.appendingPathComponent(manifestName))
        try FileManager.default.setAttributes([.posixPermissions: 0o644],
            ofItemAtPath: directory.appendingPathComponent(plistName).path)
        try FileManager.default.setAttributes([.posixPermissions: 0o600],
            ofItemAtPath: directory.appendingPathComponent(manifestName).path)

        let request = HelperPluginFilterMutationRequest(requestID: UUID(), pluginID: pluginID,
            action: .replaceSoftAssociations, dylibFileName: dylibName, plistFileName: plistName,
            targetBundleIdentifier: "com.example.host", expectedPlistSHA256: plistHash,
            expectedManifestSHA256: SHA256Digest.hex(oldManifest), createdAt: Date(),
            desiredSoftAssociations: [
                HelperPluginSoftAssociation(bundleIdentifier: "com.example.target", isEnabled: false),
                HelperPluginSoftAssociation(bundleIdentifier: "com.example.second", isEnabled: false)
            ])
        let proof = try HelperOwnershipProof(pluginID: pluginID, dylibFileName: dylibName,
            plistFileName: plistName, dylibSHA256: dylibHash, plistSHA256: plistHash,
            manifestSchemaVersion: 3, manifestSHA256: SHA256Digest.hex(oldManifest),
            binaryIdentityVerified: true)
        let prepared = HelperPluginFilterMutationAuthorizer.PreparedMutation(request: request,
            ownershipProof: proof, previousPlistData: plist, replacementPlistData: plist,
            previousManifestData: oldManifest, replacementManifestData: newManifest,
            disposition: .preparedForAtomicCommit)
        let transaction = try HelperPluginFilterConfigurationTransaction(directoryPath: directory.path)
        return Fixture(directory: directory, pluginID: pluginID, plistName: plistName,
            manifestName: manifestName, oldPlist: plist, newPlist: plist,
            oldManifest: oldManifest, newManifest: newManifest,
            prepared: prepared, transaction: transaction)
    }

    private func withRootFixture(_ body: (Fixture) throws -> Void) throws {
        guard geteuid() == 0 else { throw XCTSkip("Root-owned filesystem transaction test") }
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        try body(fixture)
    }

    func testEveryJournalPhaseRecoversDeterministically() throws {
        let crashPhases: [HelperPluginFilterConfigurationTransaction.Phase] = [
            .prepared, .staged, .backedUp, .replacingPlist, .replacingManifest, .committed
        ]
        for phase in crashPhases {
            try withRootFixture { fixture in
                XCTAssertThrowsError(try fixture.transaction.execute(fixture.prepared, simulateCrashAfter: phase),
                    "Expected injected interruption after \(phase)") { error in
                        XCTAssertEqual(error as? HelperPluginFilterConfigurationTransaction.Failure,
                                       .injectedCrash(phase))
                    }
                XCTAssertTrue(try fixture.transaction.inspectPendingJournal())
                XCTAssertTrue(try fixture.transaction.reconcile())
                let plist = try Data(contentsOf: fixture.directory.appendingPathComponent(fixture.plistName))
                let manifest = try Data(contentsOf: fixture.directory.appendingPathComponent(fixture.manifestName))
                if phase == .committed {
                    XCTAssertEqual(plist, fixture.newPlist)
                    XCTAssertEqual(manifest, fixture.newManifest)
                } else {
                    XCTAssertEqual(plist, fixture.oldPlist, "Plist rollback failed after \(phase)")
                    XCTAssertEqual(manifest, fixture.oldManifest, "Manifest rollback failed after \(phase)")
                }
                XCTAssertFalse(try fixture.transaction.inspectPendingJournal())
            }
        }
    }

    func testSuccessfulCommitReplacesManifestAndPreservesPlistBytes() throws {
        try withRootFixture { fixture in
            let receipt = try fixture.transaction.execute(fixture.prepared)
            XCTAssertEqual(receipt.pluginID, fixture.pluginID)
            XCTAssertEqual(receipt.plistSHA256, SHA256Digest.hex(fixture.newPlist))
            XCTAssertEqual(receipt.manifestSHA256, SHA256Digest.hex(fixture.newManifest))
            XCTAssertEqual(try Data(contentsOf: fixture.directory.appendingPathComponent(fixture.plistName)),
                           fixture.oldPlist, "Association-only commit must preserve Filter.plist bytes")
            XCTAssertEqual(try Data(contentsOf: fixture.directory.appendingPathComponent(fixture.manifestName)),
                           fixture.newManifest)
            XCTAssertFalse(try fixture.transaction.inspectPendingJournal())
        }
    }

    func testRecoveryFailsClosedWhenDestinationContainsForeignBytes() throws {
        try withRootFixture { fixture in
            XCTAssertThrowsError(try fixture.transaction.execute(fixture.prepared, simulateCrashAfter: .replacingManifest))
            let foreign = Data("foreign modification".utf8)
            try foreign.write(to: fixture.directory.appendingPathComponent(fixture.plistName))
            XCTAssertThrowsError(try fixture.transaction.reconcile()) { error in
                XCTAssertEqual(error as? HelperPluginFilterConfigurationTransaction.Failure, .manualIntervention)
            }
            XCTAssertTrue(try fixture.transaction.inspectPendingJournal())
            XCTAssertEqual(try Data(contentsOf: fixture.directory.appendingPathComponent(fixture.plistName)), foreign)
        }
    }

    func testRepeatedRecoveryIsIdempotentAfterJournalCleared() throws {
        try withRootFixture { fixture in
            XCTAssertThrowsError(try fixture.transaction.execute(fixture.prepared, simulateCrashAfter: .replacingPlist))
            XCTAssertTrue(try fixture.transaction.reconcile())
            XCTAssertFalse(try fixture.transaction.reconcile())
            XCTAssertEqual(try Data(contentsOf: fixture.directory.appendingPathComponent(fixture.plistName)), fixture.oldPlist)
            XCTAssertEqual(try Data(contentsOf: fixture.directory.appendingPathComponent(fixture.manifestName)), fixture.oldManifest)
        }
    }
}
