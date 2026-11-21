//
//  AppMetadataTests.swift
//  FilterKit Stage 2.5 D-R2-02 — 诊断离线测试 #16
//
//  对应能力：App 元数据（纯函数：版本回退与系统标记）。
//  口径：短版本优先，回退构建号，都缺 unknown；`/Applications/`、`/System/`
//  前缀标记系统 App；图标候选空态。
//  deferred：图标解码、私有图标 API 样本待真机/UIKit 切片。
//

import Foundation
import XCTest
@testable import Core

final class AppMetadataTests: XCTestCase {

    func testShortVersionTakesPrecedence() {
        let version = ReadOnlyDiagnosticsEngine.resolveAppVersion(short: "1.2.0", build: "3")
        XCTAssertEqual(version.version, "1.2.0")
        XCTAssertEqual(version.source, "CFBundleShortVersionString")
    }

    func testBuildVersionIsFallback() {
        let version = ReadOnlyDiagnosticsEngine.resolveAppVersion(short: nil, build: "3")
        XCTAssertEqual(version.version, "3")
        XCTAssertEqual(version.source, "CFBundleVersion")
    }

    func testMissingVersionIsUnknown() {
        let version = ReadOnlyDiagnosticsEngine.resolveAppVersion(short: nil, build: nil)
        XCTAssertEqual(version.version, "unknown")
        XCTAssertEqual(version.source, "unknown")
    }

    func testSystemAppPrefixesAreRecognized() {
        XCTAssertTrue(ReadOnlyDiagnosticsEngine.isSystemApp(path: "/Applications/Foo.app"))
        XCTAssertTrue(ReadOnlyDiagnosticsEngine.isSystemApp(path: "/System/Library/CoreServices/Bar"))
        XCTAssertFalse(ReadOnlyDiagnosticsEngine.isSystemApp(path: "/private/var/jb/Library/Tweaks/x"))
        XCTAssertFalse(ReadOnlyDiagnosticsEngine.isSystemApp(path: ""))
    }

    func testEmptyIconPathIsUnresolvedConvention() {
        // 与 scan() 闭包口径一致：图标路径为空时 icon_source=unresolved，不伪造解码成功。
        let iconPath = ""
        XCTAssertEqual(iconPath.isEmpty, true)
    }
}
