import XCTest
@testable import FilterKit

final class HelperInstallerRecoveryAcceptanceRunnerTests: XCTestCase {
    func testAcceptanceReportRoundTripsAsSortedJSON() throws {
        let report = HelperInstallerRecoveryAcceptanceRunner.Report(
            schemaVersion: 1, transactionID: "00000000-0000-0000-0000-000000000001",
            result: .keepServiceStopped, journalSequence: 4,
            journalHeadHash: String(repeating: "a", count: 64),
            active: [], staged: [], previous: [],
            pointerMatchesObservedArtifacts: false, pointerReleaseIdentifier: nil,
            pointerGeneration: nil, ownershipVerified: false,
            serviceLabel: "cn.yfen.filterkit.helper",
            serviceObserverCodeIdentitySHA256: String(repeating: "b", count: 64),
            serviceState: "unknown", evidenceDigest: String(repeating: "c", count: 64),
            executionAuthorized: false,
            limitations: ["read-only"])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(report)
        let decoded = try JSONDecoder().decode(
            HelperInstallerRecoveryAcceptanceRunner.Report.self, from: data)
        XCTAssertEqual(decoded, report)
        XCTAssertFalse(decoded.executionAuthorized)
    }

    func testReportSchemaCarriesAllThreeArtifactInventories() throws {
        let report = HelperInstallerRecoveryAcceptanceRunner.Report(
            schemaVersion: 1, transactionID: "tx", result: .reviewOnly,
            journalSequence: 1, journalHeadHash: String(repeating: "d", count: 64),
            active: [], staged: [], previous: [],
            pointerMatchesObservedArtifacts: true, pointerReleaseIdentifier: "release-1",
            pointerGeneration: 1, ownershipVerified: true,
            serviceLabel: "cn.yfen.filterkit.helper",
            serviceObserverCodeIdentitySHA256: String(repeating: "e", count: 64),
            serviceState: "stopped", evidenceDigest: String(repeating: "f", count: 64),
            executionAuthorized: false, limitations: [])
        XCTAssertEqual(report.schemaVersion, 1)
        XCTAssertTrue(report.active.isEmpty)
        XCTAssertTrue(report.staged.isEmpty)
        XCTAssertTrue(report.previous.isEmpty)
        XCTAssertFalse(report.executionAuthorized)
    }
}
