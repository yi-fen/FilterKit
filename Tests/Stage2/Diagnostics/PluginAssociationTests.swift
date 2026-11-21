//
//  PluginAssociationTests.swift
//  FilterKit Stage 2.5 D-R2-02 — 诊断离线测试 #17
//
//  对应能力：插件↔App 静态关联（纯聚合：`buildAssociations` + `associationSummary`）。
//  口径：Bundle/Executable 精确匹配；global；unmatched_target；
//  unresolved_non_bundle_rule；invalid_configuration；关联行 `loaded=unknown`；
//  静态匹配 ≠ 实际注入成功。
//  deferred：App→插件反向索引、持久化损坏隔离待 0.1-E。
//

import Foundation
import XCTest
@testable import Core

final class PluginAssociationTests: XCTestCase {

    private let applications: [[String: String]] = [
        ["bundle_id": "com.a", "executable": "App"]
    ]

    func testBundleExactMatchProducesBundleAssociation() {
        let filters: [[String: String]] = [["bundles": "com.a"]]
        let rows = ReadOnlyDiagnosticsEngine.buildAssociations(applications: applications, filters: filters)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0]["match_type"], "bundle")
        XCTAssertEqual(rows[0]["category"], "exact_match")
        XCTAssertEqual(rows[0]["loaded"], "unknown")
        XCTAssertEqual(rows[0]["evidence"], "static_filter_match_only")
    }

    func testExecutableMatchProducesExecutableAssociation() {
        let filters: [[String: String]] = [["executables": "App"]]
        let rows = ReadOnlyDiagnosticsEngine.buildAssociations(applications: applications, filters: filters)
        XCTAssertEqual(rows.first?["match_type"], "executable")
        XCTAssertEqual(rows.first?["category"], "exact_match")
    }

    func testGlobalFilterIsNotExactMatch() {
        let filters: [[String: String]] = [["global": "true"]]
        let rows = ReadOnlyDiagnosticsEngine.buildAssociations(applications: applications, filters: filters)
        XCTAssertEqual(rows.first?["category"], "global")
        XCTAssertEqual(rows.first?["is_global"], "true")
        XCTAssertNotEqual(rows.first?["category"], "exact_match")
    }

    func testUnmatchedTargetIsReportedWithNoneRow() {
        let filters: [[String: String]] = [["unmatched_bundle_ids": "com.nope"]]
        let rows = ReadOnlyDiagnosticsEngine.buildAssociations(applications: applications, filters: filters)
        XCTAssertEqual(rows.first?["category"], "unmatched_target")
        XCTAssertEqual(rows.first?["match_type"], "none")
        XCTAssertEqual(rows.first?["matched_app_count"], "0")
    }

    func testInvalidConfigurationCategory() {
        let filters: [[String: String]] = [["parse_status": "not_parsed"]]
        let rows = ReadOnlyDiagnosticsEngine.buildAssociations(applications: applications, filters: filters)
        XCTAssertEqual(rows.first?["category"], "invalid_configuration")
    }

    func testUnresolvedNonBundleRuleCategory() {
        let filters: [[String: String]] = [["bundles": "", "executables": ""]]
        let rows = ReadOnlyDiagnosticsEngine.buildAssociations(applications: applications, filters: filters)
        XCTAssertEqual(rows.first?["category"], "unresolved_non_bundle_rule")
    }

    func testAssociationSummaryCountsGlobalAndUnmatched() {
        let filters: [[String: String]] = [
            ["global": "true"],
            ["unmatched_bundle_ids": "com.nope"]
        ]
        let summary = ReadOnlyDiagnosticsEngine.associationSummary(filters: filters, plugins: [])
        XCTAssertEqual(summary.global, 1)
        XCTAssertEqual(summary.unmatched, 1)
    }

    func testAssociationSummaryComputesMissingDylibAndMissingPlist() {
        let plugins: [[String: String]] = [
            ["path": "/x/Foo.dylib"],
            ["path": "/x/Baz.dylib"]
        ]
        let filters: [[String: String]] = [
            ["plist_path": "/x/Foo.plist"],
            ["plist_path": "/x/Bar.plist"]
        ]
        let summary = ReadOnlyDiagnosticsEngine.associationSummary(filters: filters, plugins: plugins)
        XCTAssertEqual(summary.missingDylib, 1) // Bar.plist 无对应 dylib
        XCTAssertEqual(summary.missingPlist, 1) // Baz.dylib 无对应 plist
    }
}
