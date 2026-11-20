//
//  PermissionProbeReportTests.swift
//  FilterKit Stage 2 — PermissionProbe D1（报告统计与往返）
//
//  覆盖规格 §5：空证据统计全 0；多证据各状态计数；notExecuted 不计 failed；
//  unknown 不计 passed/failed；证据数组顺序保持；报告 Codable 往返。
//

import Foundation
import XCTest
@testable import Models

final class PermissionProbeReportTests: XCTestCase {

    private func evidence(_ id: String, _ status: ProbeStatus) -> ProbeEvidence {
        ProbeEvidence(probeID: id, status: status)
    }

    func testEmptyReportCountsAreZero() {
        let report = PermissionProbeReport(evidence: [])
        XCTAssertEqual(report.totalCount, 0)
        XCTAssertEqual(report.passedCount, 0)
        XCTAssertEqual(report.failedCount, 0)
        XCTAssertEqual(report.deniedCount, 0)
        XCTAssertEqual(report.unavailableCount, 0)
        XCTAssertEqual(report.notExecutedCount, 0)
        XCTAssertEqual(report.unknownCount, 0)
    }

    func testMixedStatusCounts() {
        let report = PermissionProbeReport(evidence: [
            evidence("E1", .passed),
            evidence("E2", .passed),
            evidence("E3", .failed),
            evidence("E4", .permissionDenied),
            evidence("E5", .unavailable),
            evidence("E6", .notExecuted),
            evidence("E7", .unknown)
        ])
        XCTAssertEqual(report.totalCount, 7)
        XCTAssertEqual(report.passedCount, 2)
        XCTAssertEqual(report.failedCount, 1)
        XCTAssertEqual(report.deniedCount, 1)
        XCTAssertEqual(report.unavailableCount, 1)
        XCTAssertEqual(report.notExecutedCount, 1)
        XCTAssertEqual(report.unknownCount, 1)
    }

    func testNotExecutedIsNotCountedAsFailed() {
        let report = PermissionProbeReport(evidence: [
            evidence("E1", .notExecuted),
            evidence("E2", .notExecuted)
        ])
        XCTAssertEqual(report.failedCount, 0)
        XCTAssertEqual(report.notExecutedCount, 2)
    }

    func testUnknownIsNotCountedAsPassedOrFailed() {
        let report = PermissionProbeReport(evidence: [evidence("E1", .unknown)])
        XCTAssertEqual(report.passedCount, 0)
        XCTAssertEqual(report.failedCount, 0)
        XCTAssertEqual(report.unknownCount, 1)
    }

    func testEvidenceOrderIsPreserved() throws {
        let evidence = [
            evidence("E1", .passed),
            evidence("E2", .failed),
            evidence("E3", .unknown)
        ]
        let report = PermissionProbeReport(generatedAt: "2026-11-20T00:00:00Z", evidence: evidence)
        let data = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(PermissionProbeReport.self, from: data)
        XCTAssertEqual(decoded.evidence.map(\.probeID), ["E1", "E2", "E3"])
        XCTAssertEqual(decoded, report)
    }

    func testReportRoundTrip() throws {
        let report = PermissionProbeReport(
            schemaVersion: 1,
            generatedAt: "2026-11-20T00:00:00Z",
            evidence: [
                ProbeEvidence(probeID: "JBROOT-ACCESS", category: .jbroot, status: .passed,
                              observedValue: "Entries: 4"),
                ProbeEvidence(probeID: "SANDBOX-CHECK", category: .sandbox, status: .unknown)
            ]
        )
        let data = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(PermissionProbeReport.self, from: data)
        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.generatedAt, report.generatedAt)
        XCTAssertEqual(decoded, report)
    }
}
