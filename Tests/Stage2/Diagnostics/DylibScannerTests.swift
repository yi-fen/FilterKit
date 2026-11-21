//
//  DylibScannerTests.swift
//  FilterKit Stage 2.5 D-R2-02 — 诊断离线测试 #3
//
//  对应能力：dylib 文件扫描枚举（纯表面：扩展名/类型归类辅助）。
//  deferred：目录遍历、可执行位、逐文件 lstat 待真机；跨根去重见挂起任务 #331。
//

import Foundation
import XCTest
@testable import Core

final class DylibScannerTests: XCTestCase {

    func testExtensionKeyLowercasesAndReportsNoExtensionMarker() {
        XCTAssertEqual(ReadOnlyDiagnosticsEngine.extensionKey("Foo.dylib"), "dylib")
        XCTAssertEqual(ReadOnlyDiagnosticsEngine.extensionKey("libellekit.DYLIB"), "dylib")
        XCTAssertEqual(ReadOnlyDiagnosticsEngine.extensionKey("noext"), "(无扩展名)")
    }

    func testPathCategoryClassifiesKnownPrefixes() {
        XCTAssertEqual(ReadOnlyDiagnosticsEngine.pathCategory("/usr/lib/libellekit.dylib"), "/usr/lib")
        XCTAssertEqual(ReadOnlyDiagnosticsEngine.pathCategory("/usr/bin/dpkg"), "/usr/bin")
        XCTAssertEqual(ReadOnlyDiagnosticsEngine.pathCategory("/usr/sbin/launchctl"), "/usr/sbin")
        XCTAssertEqual(ReadOnlyDiagnosticsEngine.pathCategory("/Library/TweakInject/x"), "/Library")
        XCTAssertEqual(ReadOnlyDiagnosticsEngine.pathCategory("/Applications/Foo.app"), "/Applications")
        XCTAssertEqual(ReadOnlyDiagnosticsEngine.pathCategory("/System/Library/..."), "/System")
        XCTAssertEqual(ReadOnlyDiagnosticsEngine.pathCategory("/var/jb/var/lib/dpkg/status"), "/var")
        XCTAssertEqual(ReadOnlyDiagnosticsEngine.pathCategory("/tmp/unknown"), "other")
    }

    func testDylibIsNotConfigurationOrResourceExtension() {
        XCTAssertFalse(ReadOnlyDiagnosticsEngine.isConfigurationExtension("dylib"))
        XCTAssertFalse(ReadOnlyDiagnosticsEngine.isResourceExtension("dylib"))
        XCTAssertFalse(ReadOnlyDiagnosticsEngine.isTextExtension("dylib"))
    }

    func testDylibSuffixMatchingIsLowerCaseInsensitive() {
        // 与 scan() 内联口径一致：名称小写后匹配 `.dylib` 后缀。
        XCTAssertTrue("libElleKit.dylib".lowercased().hasSuffix(".dylib"))
        XCTAssertTrue("libElleKit.DYLIB".lowercased().hasSuffix(".dylib"))
        XCTAssertFalse("libElleKit.plist".lowercased().hasSuffix(".dylib"))
    }
}
