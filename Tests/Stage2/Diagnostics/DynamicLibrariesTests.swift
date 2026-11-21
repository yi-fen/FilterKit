//
//  DynamicLibrariesTests.swift
//  FilterKit Stage 2.5 D-R2-02 — 诊断离线测试 #2
//
//  对应能力：动态库目录枚举/可访问性（纯表面：报告结构与空态口径）。
//  deferred：路径存在性/可读性、`opendir` errno、realpath、逐目录枚举待真机
//  与 FS 接缝（D-R2-03）；本文件只断言行键齐全与空态不伪造可访问记录。
//

import Foundation
import XCTest
@testable import Core

final class DynamicLibrariesTests: XCTestCase {

    private let directoryKeys = [
        "path", "exists", "directory", "readable", "is_symlink", "enumerable", "entry_count"
    ]

    func testScanReportDirectoryRowsCarryRequiredKeys() throws {
        let report = ReadOnlyDiagnosticsEngine().scan()
        for row in report.dynamicLibraryDirectories {
            for key in directoryKeys {
                XCTAssertNotNil(row[key], "目录行缺少键 \(key)")
            }
            XCTAssertFalse((row["path"] ?? "").isEmpty)
        }
    }

    func testNonEnumerableRowReportsZeroEntryCount() {
        let report = ReadOnlyDiagnosticsEngine().scan()
        for row in report.dynamicLibraryDirectories where row["enumerable"] != "true" {
            XCTAssertEqual(row["entry_count"], "0")
        }
    }

    func testNoEnumerableRowWithoutPath() {
        let report = ReadOnlyDiagnosticsEngine().scan()
        for row in report.dynamicLibraryDirectories where row["enumerable"] == "true" {
            XCTAssertFalse((row["path"] ?? "").isEmpty)
        }
    }

    func testReportExposesTopLevelSections() {
        let report = ReadOnlyDiagnosticsEngine().scan()
        // 空态下各段必须是数组（可为空），不得为 nil 或缺失。
        XCTAssertTrue(report.roots is [[String: String]])
        XCTAssertTrue(report.plugins is [[String: String]])
        XCTAssertTrue(report.filters is [[String: String]])
        XCTAssertTrue(report.injectorEvidence is [[String: String]])
        XCTAssertTrue(report.packages is [[String: String]])
    }
}
