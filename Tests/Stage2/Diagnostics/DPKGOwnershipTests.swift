//
//  DPKGOwnershipTests.swift
//  FilterKit Stage 2.5 D-R2-02 — 诊断离线测试 #8
//
//  对应能力：`.list` 文件归属（纯函数：路径归一化）。
//  deferred：`.list` 读取与物理路径存在性待 FS 接缝（D-R2-03）；归属集合聚合
//  发生在 `analyzeDpkg` 私有表面，本文件只验证归一化键口径。
//

import Foundation
import XCTest
@testable import Core

final class DPKGOwnershipTests: XCTestCase {

    func testCanonicalStripsRootPrefix() {
        let path = "/private/var/jb/Library/ElleKit/DynamicLibraries/x.dylib"
        XCTAssertEqual(ReadOnlyDiagnosticsEngine.canonicalDpkgPath(path, root: "/private/var/jb"),
                       "/Library/ElleKit/DynamicLibraries/x.dylib")
    }

    func testCanonicalStripsVarJBPrefixWithoutRoot() {
        let path = "/var/jb/Library/MobileSubstrate/DynamicLibraries/y.plist"
        XCTAssertEqual(ReadOnlyDiagnosticsEngine.canonicalDpkgPath(path, root: nil),
                       "/Library/MobileSubstrate/DynamicLibraries/y.plist")
    }

    func testCanonicalLeavesNonRootAbsolutePath() {
        XCTAssertEqual(ReadOnlyDiagnosticsEngine.canonicalDpkgPath("/usr/lib/z", root: "/var/jb"),
                       "/usr/lib/z")
    }

    func testCanonicalJBRootMapsToSlash() {
        XCTAssertEqual(ReadOnlyDiagnosticsEngine.canonicalDpkgPath("/var/jb", root: nil), "/")
    }

    func testCanonicalStandardizesDoubleSlash() {
        XCTAssertEqual(ReadOnlyDiagnosticsEngine.canonicalDpkgPath("/Library//x.plist", root: nil),
                       "/Library/x.plist")
    }

    func testPhysicalPrependsRootToLogicalPath() {
        XCTAssertEqual(
            ReadOnlyDiagnosticsEngine.physicalDpkgPath("/Library/x.dylib", root: "/private/var/jb"),
            "/private/var/jb/Library/x.dylib")
    }

    func testPhysicalKeepsVarJBPathUnchanged() {
        let path = "/var/jb/Library/y.plist"
        XCTAssertEqual(ReadOnlyDiagnosticsEngine.physicalDpkgPath(path, root: nil), path)
    }

    func testPhysicalKeepsUnknownAbsolutePathWithoutRoot() {
        XCTAssertEqual(ReadOnlyDiagnosticsEngine.physicalDpkgPath("/usr/lib/z", root: nil),
                       "/usr/lib/z")
    }

    func testOwnershipRowKeyIsCanonicalLogicalPath() {
        // 与 analyzeDpkg 归属行口径一致：分组键先经 canonical 归一化，
        // 物理存在性与多包集合写入待 FS 接缝后补离线夹具。
        let logical = ReadOnlyDiagnosticsEngine.canonicalDpkgPath(
            "/var/jb/Library/x.dylib", root: nil)
        XCTAssertEqual(logical, "/Library/x.dylib")
    }
}
