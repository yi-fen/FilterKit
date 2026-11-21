//
//  FilterRulesTests.swift
//  FilterKit Stage 2.5 D-R2-02 — 诊断离线测试 #5
//
//  对应能力：Bundles/Executables/Classes 解析（纯函数 `parseFilterDictionary`）。
//  口径：`*` 置 global 但不计 exact_match；Executables 按小写匹配；非数组值、
//  非字符串项、空串进 warnings；Classes 仅保留不映射 BundleID。
//  deferred：`*` loader 语义待 ElleKit 源码核实，scan 行恒 `protocol_verified=false`。
//

import Foundation
import XCTest
@testable import Core

final class FilterRulesTests: XCTestCase {

    func testWildcardMarksGlobalButNotExactMatch() {
        let parsed = ReadOnlyDiagnosticsEngine.parseFilterDictionary(
            ["Bundles": ["*"]], installedBundleIDs: [], installedExecutables: [])
        XCTAssertEqual(parsed["global"], "true")
        XCTAssertEqual(parsed["bundles"], "*")
        XCTAssertEqual(parsed["matched_bundle_ids"], "")
        XCTAssertEqual(parsed["unmatched_bundle_ids"], "")
        XCTAssertTrue((parsed["warnings"] ?? "").contains("*"))
    }

    func testMatchedAndUnmatchedBundlesArePartitioned() {
        let parsed = ReadOnlyDiagnosticsEngine.parseFilterDictionary(
            ["Bundles": ["com.a", "com.nope"]],
            installedBundleIDs: ["com.a"], installedExecutables: [])
        XCTAssertEqual(parsed["matched_bundle_ids"], "com.a")
        XCTAssertEqual(parsed["unmatched_bundle_ids"], "com.nope")
    }

    func testExecutableMatchingIsCaseInsensitive() {
        let parsed = ReadOnlyDiagnosticsEngine.parseFilterDictionary(
            ["Executables": ["ExampleApp"]],
            installedBundleIDs: [], installedExecutables: ["exampleapp"])
        XCTAssertEqual(parsed["matched_executables"], "ExampleApp")
        XCTAssertEqual(parsed["unmatched_executables"], "")
    }

    func testNonArrayBundleValueEmitsWarning() {
        let parsed = ReadOnlyDiagnosticsEngine.parseFilterDictionary(
            ["Bundles": "com.a"], installedBundleIDs: ["com.a"], installedExecutables: [])
        XCTAssertTrue((parsed["warnings"] ?? "").contains("不是数组"))
        XCTAssertEqual(parsed["bundles"], "")
    }

    func testNonStringElementIsSkippedWithWarning() {
        let parsed = ReadOnlyDiagnosticsEngine.parseFilterDictionary(
            ["Bundles": ["com.a", NSNumber(value: 1)]],
            installedBundleIDs: ["com.a"], installedExecutables: [])
        XCTAssertTrue((parsed["warnings"] ?? "").contains("非字符串"))
        XCTAssertEqual(parsed["bundles"], "com.a")
    }

    func testEmptyStringIsSkippedWithWarning() {
        let parsed = ReadOnlyDiagnosticsEngine.parseFilterDictionary(
            ["Bundles": ["   "]], installedBundleIDs: [], installedExecutables: [])
        XCTAssertTrue((parsed["warnings"] ?? "").contains("空字符串"))
        XCTAssertEqual(parsed["entry_count"], "0")
        XCTAssertEqual(parsed["valid"], "false")
    }

    func testClassesAreRetainedWithoutBundleMapping() {
        let parsed = ReadOnlyDiagnosticsEngine.parseFilterDictionary(
            ["Classes": ["Hook"]],
            installedBundleIDs: [], installedExecutables: [])
        XCTAssertEqual(parsed["classes"], "Hook")
        XCTAssertEqual(parsed["matched_bundle_ids"], "")
        XCTAssertEqual(parsed["entry_count"], "1")
        XCTAssertEqual(parsed["valid"], "true")
    }

    func testOtherKeysAreCollectedSorted() {
        let parsed = ReadOnlyDiagnosticsEngine.parseFilterDictionary(
            ["Zeta": "1", "Alpha": "2", "Bundles": ["com.a"]],
            installedBundleIDs: ["com.a"], installedExecutables: [])
        XCTAssertEqual(parsed["other_keys"], "Alpha,Zeta")
    }
}
