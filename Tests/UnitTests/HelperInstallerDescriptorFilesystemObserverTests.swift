import XCTest
@testable import FilterKit

final class HelperInstallerDescriptorFilesystemObserverTests: XCTestCase {
    func testReleasePointerRequiresExactArtifactInventory() {
        let hashes = [
            "executable": String(repeating: "a", count: 64),
            "deploymentManifest": String(repeating: "b", count: 64),
            "launchDaemon": String(repeating: "c", count: 64)
        ]
        let valid = HelperInstallerDescriptorFilesystemObserver.ReleasePointer(
            schemaVersion: 2, transactionID: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!, releaseIdentifier: "r12", generation: 12, artifactHashes: hashes)
        XCTAssertTrue(valid.validate())
        var incomplete = hashes
        incomplete.removeValue(forKey: "launchDaemon")
        let invalid = HelperInstallerDescriptorFilesystemObserver.ReleasePointer(
            schemaVersion: 2, transactionID: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!, releaseIdentifier: "r12", generation: 12, artifactHashes: incomplete)
        XCTAssertFalse(invalid.validate())
    }

    func testReleasePointerRejectsInvalidGenerationAndDigest() {
        let invalidGeneration = HelperInstallerDescriptorFilesystemObserver.ReleasePointer(
            schemaVersion: 2, transactionID: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!, releaseIdentifier: "r12", generation: 0,
            artifactHashes: ["executable": String(repeating: "a", count: 64),
                             "deploymentManifest": String(repeating: "b", count: 64),
                             "launchDaemon": String(repeating: "c", count: 64)])
        XCTAssertFalse(invalidGeneration.validate())
        let invalidDigest = HelperInstallerDescriptorFilesystemObserver.ReleasePointer(
            schemaVersion: 2, transactionID: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!, releaseIdentifier: "r12", generation: 12,
            artifactHashes: ["executable": "not-a-digest",
                             "deploymentManifest": String(repeating: "b", count: 64),
                             "launchDaemon": String(repeating: "c", count: 64)])
        XCTAssertFalse(invalidDigest.validate())
    }


    func testLegacyPointerSchemaIsRejectedAfterTransactionBindingUpgrade() {
        let pointer = HelperInstallerDescriptorFilesystemObserver.ReleasePointer(
            schemaVersion: 1, transactionID: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!,
            releaseIdentifier: "r12", generation: 12,
            artifactHashes: ["executable": String(repeating: "a", count: 64),
                             "deploymentManifest": String(repeating: "b", count: 64),
                             "launchDaemon": String(repeating: "c", count: 64)])
        XCTAssertFalse(pointer.validate())
    }

    func testMissingAndPresentArtifactStatesRemainDistinct() {
        let missing = HelperInstallerDescriptorFilesystemObserver.ArtifactState.missing
        let record = HelperInstallerDescriptorFilesystemObserver.FileRecord(
            relativePath: "usr/libexec/filterkit-helper",
            sha256: String(repeating: "a", count: 64), byteCount: 10,
            ownerUID: 0, groupID: 0, mode: 0o755, device: 1, inode: 2)
        XCTAssertNotEqual(missing, .present(record))
        XCTAssertEqual(.present(record), .present(record))
    }

    func testRelativePathTraversalIsRejectedBeforeFilesystemAccess() {
        let observer = HelperInstallerDescriptorFilesystemObserver(jbRootPath: "/")
        XCTAssertThrowsError(try observer.observeFile(relativePath: "../etc/passwd")) { error in
            XCTAssertEqual(error as? HelperInstallerDescriptorFilesystemObserver.ObservationError,
                           .invalidRelativePath)
        }
    }
}
