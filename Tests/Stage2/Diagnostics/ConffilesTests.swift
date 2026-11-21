//
//  ConffilesTests.swift
//  FilterKit Stage 2.5 D-R2-02 — 诊断离线测试 #12
//
//  对应能力：Conffiles 双渠道识别（纯函数：status 字段解析）。
//  口径：路径+MD5 行解析；非绝对路径忽略；双渠道合并去重；单渠道缺失不武断。
//  deferred：`info/<pkg>.conffiles` 文件渠道读取待 FS 接缝（D-R2-03）。
//

import Foundation
import XCTest
@testable import Core

final class ConffilesTests: XCTestCase {

    func testParsesAbsolutePathWithHashSuffix() {
        let paths = ReadOnlyDiagnosticsEngine.conffilePathsFromFields(
            ["Conffiles": "/etc/a.plist abc123\n/Library/b.plist def456"])
        XCTAssertEqual(paths, Set(["/etc/a.plist", "/Library/b.plist"]))
    }

    func testIgnoresRelativePaths() {
        let paths = ReadOnlyDiagnosticsEngine.conffilePathsFromFields(
            ["Conffiles": "relative/path.conf\n/etc/absolute.plist hash"])
        XCTAssertEqual(paths, Set(["/etc/absolute.plist"]))
    }

    func testMissingKeyYieldsEmptySet() {
        XCTAssertTrue(ReadOnlyDiagnosticsEngine.conffilePathsFromFields([:]).isEmpty)
    }

    func testEmptyConffilesFieldYieldsEmptySet() {
        XCTAssertTrue(ReadOnlyDiagnosticsEngine.conffilePathsFromFields(
            ["Conffiles": ""]).isEmpty)
    }

    func testDuplicatePathsAreDeduplicated() {
        let paths = ReadOnlyDiagnosticsEngine.conffilePathsFromFields(
            ["Conffiles": "/etc/a.plist h1\n/etc/a.plist h2"])
        XCTAssertEqual(paths, Set(["/etc/a.plist"]))
    }

    func testFieldChannelIsIndependentOfFileChannel() {
        // 文件渠道（`.conffiles`）由私有包装 `conffilePaths(fields:infoDirectory:)`
        // 叠加；离线纯表面只负责 status 字段渠道，文件渠道读取待 FS 接缝。
        let fieldOnly = ReadOnlyDiagnosticsEngine.conffilePathsFromFields(
            ["Conffiles": "/etc/field.plist h"])
        XCTAssertEqual(fieldOnly, Set(["/etc/field.plist"]))
    }
}
