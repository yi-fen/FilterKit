//
//  DPKGStatusParserTests.swift
//  FilterKit Stage 2.5 D-R2-02 — 诊断离线测试 #7
//
//  对应能力：status 读取与状态解析（纯文本记录拆分）。
//  deferred：status 候选路径探测、文件读取、非 UTF-8 包装告警待 FS 接缝（D-R2-03）。
//

import Foundation
import XCTest
@testable import Core

final class DPKGStatusParserTests: XCTestCase {

    func testSplitsRecordsByBlankLine() {
        let text = """
        Package: com.a
        Version: 1.0
        Status: install ok installed

        Package: com.b
        Version: 2.0
        Status: install ok unpacked
        """
        let (records, warnings) = ReadOnlyDiagnosticsEngine.parseDpkgStatusText(text)
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records[0]["Package"], "com.a")
        XCTAssertEqual(records[1]["Version"], "2.0")
        XCTAssertTrue(warnings.isEmpty)
    }

    func testContinuationLineJoinsWithNewline() {
        let text = """
        Package: com.a
        Description: line1
         line2
        """
        let (records, _) = ReadOnlyDiagnosticsEngine.parseDpkgStatusText(text)
        XCTAssertEqual(records.first?["Description"], "line1\nline2")
    }

    func testMalformedFieldLineEmitsWarning() {
        let text = """
        Package: com.a
        not-a-field-line
        """
        let (records, warnings) = ReadOnlyDiagnosticsEngine.parseDpkgStatusText(text)
        XCTAssertEqual(records.count, 1)
        XCTAssertTrue(warnings.contains("malformed_field_line"))
    }

    func testOrphanContinuationLineEmitsWarning() {
        let text = "  leading-continuation-without-key\n"
        let (records, warnings) = ReadOnlyDiagnosticsEngine.parseDpkgStatusText(text)
        XCTAssertTrue(records.isEmpty)
        XCTAssertTrue(warnings.contains("orphan_continuation_line"))
    }

    func testDuplicateFieldEmitsWarningAndKeepsRecord() {
        let text = """
        Package: com.a
        Package: com.b
        """
        let (records, warnings) = ReadOnlyDiagnosticsEngine.parseDpkgStatusText(text)
        XCTAssertEqual(records.count, 1)
        XCTAssertTrue(warnings.contains { $0.hasPrefix("duplicate_field:") })
    }

    func testEmptyAndWhitespaceTextYieldsNoRecords() {
        let empty = ReadOnlyDiagnosticsEngine.parseDpkgStatusText("")
        let whitespace = ReadOnlyDiagnosticsEngine.parseDpkgStatusText("   \n\t\n")
        XCTAssertTrue(empty.0.isEmpty)
        XCTAssertTrue(empty.1.isEmpty)
        XCTAssertTrue(whitespace.0.isEmpty)
        XCTAssertTrue(whitespace.1.isEmpty)
    }
}
