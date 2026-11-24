import XCTest
@testable import FilterKit

final class PluginIdentityAnalyzerTests: XCTestCase {
    func testSameFingerprintIsReportedAsDuplicateIdentity() {
        let first = item(id: "A.dylib", installName: "/Library/A.dylib", uuid: "UUID-A", cdhash: ["HASH-A"])
        let second = item(id: "Alias.dylib", installName: "/Library/A.dylib", uuid: "UUID-A", cdhash: ["HASH-A"])
        let result = PluginIdentityAnalyzer().analyze([first, second])
        XCTAssertEqual(result.conflicts.count, 1)
        XCTAssertEqual(result.conflicts.first?.kind, .duplicateIdentity)
        XCTAssertTrue(result.items.allSatisfy { $0.identityStatus == .duplicateIdentity })
    }

    func testSameInstallNameWithDifferentFingerprintsIsForkCollision() {
        let first = item(id: "ForkA.dylib", installName: "/usr/lib/libExample.dylib", uuid: "UUID-A", cdhash: ["HASH-A"])
        let second = item(id: "ForkB.dylib", installName: "/usr/lib/libExample.dylib", uuid: "UUID-B", cdhash: ["HASH-B"])
        let result = PluginIdentityAnalyzer().analyze([first, second])
        XCTAssertTrue(result.conflicts.contains { $0.kind == .installNameCollision })
    }

    func testSameUUIDWithDifferentCDHashesIsConflict() {
        let first = item(id: "A.dylib", installName: "/usr/lib/A.dylib", uuid: "SAME-UUID", cdhash: ["HASH-A"])
        let second = item(id: "B.dylib", installName: "/usr/lib/B.dylib", uuid: "SAME-UUID", cdhash: ["HASH-B"])
        let result = PluginIdentityAnalyzer().analyze([first, second])
        XCTAssertTrue(result.conflicts.contains { $0.kind == .uuidCDHashMismatch })
    }



    func testIdentityConflictDowngradesManagementPermissionToReadOnly() {
        let allowed = PluginManagementPermission(access: .manageable, reasonKey: "plugins.permission.filterkit_managed")
        let restricted = PluginManagementPermission.restricting(allowed,
            identityStatus: .installNameCollision, ownershipConflict: .none)
        XCTAssertFalse(restricted.canModify)
        XCTAssertEqual(restricted.access, .readOnlyIdentityConflict)
    }

    func testOwnershipConflictTakesPriorityOverIdentityStatus() {
        let allowed = PluginManagementPermission(access: .manageable, reasonKey: "plugins.permission.filterkit_managed")
        let restricted = PluginManagementPermission.restricting(allowed,
            identityStatus: .unique, ownershipConflict: .filterKitVsPackageManager)
        XCTAssertFalse(restricted.canModify)
        XCTAssertEqual(restricted.access, .readOnlyOwnershipConflict)
    }

    func testFingerprintIsOrderAndCaseNormalized() {
        let first = PluginIdentityAnalyzer.fingerprint(installNames: ["/usr/lib/A.dylib"],
            uuids: ["UUID-B", "UUID-A"], cdHashes: ["HASH-B", "HASH-A"])
        let second = PluginIdentityAnalyzer.fingerprint(installNames: ["/USR/LIB/a.DYLIB"],
            uuids: ["uuid-a", "uuid-b"], cdHashes: ["hash-a", "hash-b"])
        XCTAssertEqual(first, second)
    }

    func testNoUUIDOrCDHashRemainsInsufficientRatherThanInventingIdentity() {
        let result = PluginIdentityAnalyzer().analyze([item(id: "NoIdentity.dylib", installName: nil, uuid: nil, cdhash: [])])
        XCTAssertEqual(result.items.first?.identityStatus, .insufficientFingerprint)
        XCTAssertNil(result.items.first?.identityFingerprint)
        XCTAssertTrue(result.conflicts.isEmpty)
    }

    private func item(id: String, installName: String?, uuid: String?, cdhash: [String]) -> PluginScanItem {
        PluginScanItem(id: id, baseName: id, dylibFileName: id, plistFileName: "\(id).plist",
            manifestFileName: nil, pairingState: .paired, binaryKind: .machO, ownership: .unknown,
            filterKitPluginID: nil, packageIdentifier: nil, dylibSHA256: nil, plistSHA256: nil,
            hardBoundBundleIdentifier: nil, softAssociatedBundleIdentifiers: [], warnings: [],
            filterConfiguration: nil, managementPermission: nil,
            machOInstallName: installName, machOUUID: uuid, machOCDHashes: cdhash)
    }
}
