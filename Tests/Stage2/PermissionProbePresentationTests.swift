//
//  PermissionProbePresentationTests.swift
//  FilterKit Stage 2.4-D7 — 探针展示映射单测
//
//  核对 ProbeDiagnosticsMapper：分类分组、六态分级映射、空报告空态；
//  unknown / notExecuted 不升级为 success。纯 Foundation 映射，不访问文件系统。
//

import Foundation
import XCTest
@testable import Models
@testable import AppPresentation

final class PermissionProbePresentationTests: XCTestCase {

    private func evidence(probeID: String,
                          category: ProbeCategory,
                          status: ProbeStatus,
                          observed: String? = nil) -> ProbeEvidence {
        ProbeEvidence(
            probeID: probeID,
            operation: .inspect,
            category: category,
            status: status,
            target: "target",
            observedValue: observed
        )
    }

    func testNilReportRendersUnknownEmptyState() {
        let sections = ProbeDiagnosticsMapper.sections(nil)
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections.first?.id, "probes")
        XCTAssertEqual(sections.first?.rows.first?.status?.kind, .unknown)
    }

    func testEvidenceGroupedByCategory() {
        let report = PermissionProbeReport(evidence: [
            evidence(probeID: "jbroot.directory.access", category: .jbroot, status: .passed),
            evidence(probeID: "ellekit.directory.access", category: .ellekit, status: .failed),
            evidence(probeID: "entitlement.process", category: .entitlement, status: .unavailable)
        ])

        let sections = ProbeDiagnosticsMapper.sections(report)
        let ids = sections.map(\.id)
        XCTAssertEqual(ids, ["jbroot", "ellekit", "entitlement"])
        XCTAssertEqual(sections.first?.title, "JBROOT")
        XCTAssertEqual(sections.first?.rows.first?.label, "jbroot.directory.access")
    }

    func testStatusMappingNeverUpgradesUnknown() {
        XCTAssertEqual(ProbeDiagnosticsMapper.displayStatus(for: .unknown).kind, .unknown)
        XCTAssertEqual(ProbeDiagnosticsMapper.displayStatus(for: .notExecuted).kind, .unknown)
        XCTAssertEqual(ProbeDiagnosticsMapper.displayStatus(for: .unavailable).kind, .warning)
        XCTAssertEqual(ProbeDiagnosticsMapper.displayStatus(for: .passed).kind, .success)
        XCTAssertEqual(ProbeDiagnosticsMapper.displayStatus(for: .failed).kind, .failure)
        XCTAssertEqual(ProbeDiagnosticsMapper.displayStatus(for: .permissionDenied).kind, .failure)
    }

    func testDeniedRowMapsToFailure() {
        let report = PermissionProbeReport(evidence: [
            evidence(probeID: "sandbox.resource.access",
                     category: .sandbox,
                     status: .permissionDenied,
                     observed: "unreachable")
        ])
        let section = ProbeDiagnosticsMapper.sections(report).first
        XCTAssertEqual(section?.rows.first?.status?.kind, .failure)
        XCTAssertEqual(section?.rows.first?.value, "unreachable")
    }
}
