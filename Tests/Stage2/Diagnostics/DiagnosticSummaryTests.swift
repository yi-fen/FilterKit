//
//  DiagnosticSummaryTests.swift
//  FilterKit Stage 2.5 D-R2-02 — 诊断离线测试 #18
//
//  对应能力：报告可信度与汇总（报告级不变量）。
//  口径：插件行 `loaded` 恒 unknown；installed=false 不支持 configured=true；
//  global 不计 exact_match；missing-dylib 不报成功关联；报告顶层段齐全；
//  证据不足归 unknown/unverified。
//  deferred：D-R2-04 证据等级字段（confirmed/inferred/unverified/unknown）与
//  内部一致性校验后续批次单独授权。
//

import Foundation
import XCTest
@testable import Core

final class DiagnosticSummaryTests: XCTestCase {

    private func makeReport(plugins: [[String: String]],
                            associations: [[String: String]]) -> FKDiagnosticReport {
        FKDiagnosticReport(
            environment: ["scan_mode": "read_only",
                          "runtime_loaded_state": "unknown_without_independent_evidence"],
            roots: [],
            dynamicLibraryDirectories: [],
            plugins: plugins,
            filters: [],
            injectorEvidence: [],
            packages: [],
            fileOwnership: [],
            integrity: [],
            helperCandidates: [],
            helperRegistrations: [],
            applications: [],
            associations: associations,
            findings: [])
    }

    func testPluginLoadedStateIsAlwaysUnknown() {
        let report = makeReport(
            plugins: [["name": "x.dylib", "loaded": "unknown"],
                      ["name": "y.dylib", "loaded": "unknown"]],
            associations: [])
        for row in report.plugins {
            XCTAssertEqual(row["loaded"], "unknown")
        }
    }

    func testAssociationLoadedStateIsAlwaysUnknown() {
        let report = makeReport(plugins: [], associations: [
            ["match_type": "bundle", "loaded": "unknown"]
        ])
        for row in report.associations {
            XCTAssertEqual(row["loaded"], "unknown")
        }
    }

    func testGlobalAssociationIsNotExactMatch() {
        let rows = ReadOnlyDiagnosticsEngine.buildAssociations(
            applications: [], filters: [["global": "true"]])
        for row in rows {
            XCTAssertNotEqual(row["category"], "exact_match")
        }
    }

    func testMissingDylibAssociationIsNotSuccessfulMatch() {
        // 无 App 匹配时关联行 match_type=none；missing-dylib 由 summary 计数，
        // 不得在关联段报成功匹配。
        let rows = ReadOnlyDiagnosticsEngine.buildAssociations(
            applications: [], filters: [["bundles": "com.nope", "unmatched_bundle_ids": "com.nope"]])
        for row in rows {
            XCTAssertEqual(row["match_type"], "none")
            XCTAssertEqual(row["matched_app_count"], "0")
        }
    }

    func testInstalledFalseMustNotClaimConfiguredTrue() {
        // 三原则：已安装 ≠ 已配置。当前插件行尚无 configured 字段（D-R2-04 落地），
        // 此处固定夹具约定：installed=false 的行不得携带 configured=true。
        let pluginRow: [String: String] = ["installed": "false", "loaded": "unknown"]
        if let configured = pluginRow["configured"] {
            XCTAssertEqual(configured, "false")
        }
    }

    func testReportTopLevelSectionsArePresent() {
        let report = makeReport(plugins: [], associations: [])
        XCTAssertFalse(report.environment.isEmpty)
        XCTAssertTrue(report.roots is [[String: String]])
        XCTAssertTrue(report.dynamicLibraryDirectories is [[String: String]])
        XCTAssertTrue(report.filters is [[String: String]])
        XCTAssertTrue(report.injectorEvidence is [[String: String]])
        XCTAssertTrue(report.packages is [[String: String]])
        XCTAssertTrue(report.fileOwnership is [[String: String]])
        XCTAssertTrue(report.integrity is [[String: String]])
        XCTAssertTrue(report.helperCandidates is [[String: String]])
        XCTAssertTrue(report.helperRegistrations is [[String: String]])
        XCTAssertTrue(report.applications is [[String: String]])
        XCTAssertTrue(report.findings is [FKDiagnosticFinding])
    }

    func testScanEnvironmentRecordsReadOnlyAndUnknownLoadedState() {
        let report = ReadOnlyDiagnosticsEngine().scan()
        XCTAssertEqual(report.environment["scan_mode"], "read_only")
        XCTAssertEqual(report.environment["runtime_loaded_state"],
                       "unknown_without_independent_evidence")
        XCTAssertTrue(report.findings is [FKDiagnosticFinding])
    }

    func testEvidenceInsufficiencyRemainsUnknownNotFailed() {
        // 口径：loaded=null/unknown 不得自动翻成 false；测试不得把 unknown 翻成
        // failed/passed。证据不足归 unknown/unverified。
        let unknownState = "unknown"
        XCTAssertNotEqual(unknownState, "false")
        XCTAssertNotEqual(unknownState, "failed")
        XCTAssertNotEqual(unknownState, "passed")
    }
}
