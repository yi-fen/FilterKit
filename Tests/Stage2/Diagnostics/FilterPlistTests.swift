//
//  FilterPlistTests.swift
//  FilterKit Stage 2.5 D-R2-02 — 诊断离线测试 #4
//
//  对应能力：plist 扫描读取（纯表面：解析输入类型守卫）。
//  deferred：文件读取、损坏 plist、不可读待 FS 接缝（D-R2-03）；嵌套 `Filter`
//  字典的解包发生在 scan() 闭包内，随文件读取一并延后，本文件只验证字典形状。
//

import Foundation
import XCTest
@testable import Core

final class FilterPlistTests: XCTestCase {

    func testNilInputIsRejectedAsNonDictionary() {
        let parsed = ReadOnlyDiagnosticsEngine.parseFilterDictionary(
            nil, installedBundleIDs: [], installedExecutables: [])
        XCTAssertEqual(parsed["valid"], "false")
        XCTAssertEqual(parsed["entry_count"], "0")
        XCTAssertEqual(parsed["warnings"], "filter_not_a_dictionary")
    }

    func testArrayInputIsRejectedAsNonDictionary() {
        let parsed = ReadOnlyDiagnosticsEngine.parseFilterDictionary(
            ["com.a"], installedBundleIDs: [], installedExecutables: [])
        XCTAssertEqual(parsed["valid"], "false")
        XCTAssertEqual(parsed["warnings"], "filter_not_a_dictionary")
    }

    func testStringAndNumberInputsAreRejectedAsNonDictionary() {
        XCTAssertEqual(ReadOnlyDiagnosticsEngine.parseFilterDictionary(
            "not-a-dict", installedBundleIDs: [], installedExecutables: [])["warnings"],
            "filter_not_a_dictionary")
        XCTAssertEqual(ReadOnlyDiagnosticsEngine.parseFilterDictionary(
            NSNumber(value: 1), installedBundleIDs: [], installedExecutables: [])["warnings"],
            "filter_not_a_dictionary")
    }

    func testEmptyDictionaryIsInvalidWithZeroEntries() {
        let parsed = ReadOnlyDiagnosticsEngine.parseFilterDictionary(
            [String: Any](), installedBundleIDs: [], installedExecutables: [])
        XCTAssertEqual(parsed["valid"], "false")
        XCTAssertEqual(parsed["entry_count"], "0")
        XCTAssertEqual(parsed["bundles"], "")
        XCTAssertEqual(parsed["executables"], "")
        XCTAssertEqual(parsed["classes"], "")
    }

    func testDictionaryWithMatchedBundleParses() {
        let parsed = ReadOnlyDiagnosticsEngine.parseFilterDictionary(
            ["Bundles": ["com.a"]],
            installedBundleIDs: ["com.a"], installedExecutables: [])
        XCTAssertEqual(parsed["valid"], "true")
        XCTAssertEqual(parsed["entry_count"], "1")
        XCTAssertEqual(parsed["matched_bundle_ids"], "com.a")
        XCTAssertEqual(parsed["unmatched_bundle_ids"], "")
    }
}
