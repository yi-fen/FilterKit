//
//  JBRootDetectorTests.swift
//  FilterKit Stage 2.5 D-R2-02 — 诊断离线测试 #1
//
//  对应能力：JBROOT 定位与校验（纯表面：`.jbroot-<16hex>` 正则反解）。
//  deferred：容器存在/可读/结构标记、`jbroot()` dlsym、`.jbroot-` 目录枚举
//  待真机与 FS 接缝（D-R2-03），本文件不写伪造断言。
//

import Foundation
import XCTest
@testable import Core

final class JBRootDetectorTests: XCTestCase {

    func testExtractsRootPrefixFromPrivateContainerPath() {
        let path = "/private/var/containers/Bundle/Application/.jbroot-8D3CAE7017A11CC5/Library/ElleKit/DynamicLibraries"
        XCTAssertEqual(ReadOnlyDiagnosticsEngine.rootFromJBRootPath(path),
                       "/private/var/containers/Bundle/Application/.jbroot-8D3CAE7017A11CC5")
    }

    func testExtractsRootPrefixFromVarContainerPath() {
        let path = "/var/containers/Bundle/Application/.jbroot-ABCDEF0123456789/var/jb"
        XCTAssertEqual(ReadOnlyDiagnosticsEngine.rootFromJBRootPath(path),
                       "/var/containers/Bundle/Application/.jbroot-ABCDEF0123456789")
    }

    func testPlainJBRootPathHasNoContainerMarker() {
        XCTAssertNil(ReadOnlyDiagnosticsEngine.rootFromJBRootPath("/var/jb"))
    }

    func testRejectsShortIdentifier() {
        // 15 位十六进制不足 16 位，正则不命中。
        let path = "/var/containers/Application/.jbroot-123456789012345/Library"
        XCTAssertNil(ReadOnlyDiagnosticsEngine.rootFromJBRootPath(path))
    }

    func testRejectsNonHexIdentifier() {
        let path = "/var/containers/Application/.jbroot-XXXXXXXXXXXXXXXX/Library"
        XCTAssertNil(ReadOnlyDiagnosticsEngine.rootFromJBRootPath(path))
    }

    func testRejectsUnrelatedSystemPath() {
        XCTAssertNil(ReadOnlyDiagnosticsEngine.rootFromJBRootPath("/usr/lib/libellekit.dylib"))
    }
}
