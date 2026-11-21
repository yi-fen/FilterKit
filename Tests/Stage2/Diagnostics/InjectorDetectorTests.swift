//
//  InjectorDetectorTests.swift
//  FilterKit Stage 2.5 D-R2-02 — 诊断离线测试 #6
//
//  对应能力：注入器识别（纯表面：包关键词匹配 + 画像表 + 运行时行构造）。
//  口径：Status 含 ` installed` 才标 installed；静态与运行时证据分列；
//  运行时行 `scope=current_process_only`；空包空镜像不伪造行。
//  deferred：镜像 Info.plist 版本反查、兼容结论枚举、启停能力位待真机。
//

import Foundation
import XCTest
@testable import Core

final class InjectorDetectorTests: XCTestCase {

    private func package(_ id: String, status: String) -> [String: String] {
        ["Package": id, "Status": status, "Version": "1.0.0", "Architecture": "arm64e"]
    }

    func testKnownPackageIsClassifiedWithStaticEvidence() {
        let rows = ReadOnlyDiagnosticsEngine.identifyInjectors(
            packages: [package("com.apt.ellekit", status: "install ok installed")], runtimeImages: [])
        XCTAssertEqual(rows.count, 1)
        let row = rows[0]
        XCTAssertEqual(row["type"], "ellekit")
        XCTAssertEqual(row["installed"], "true")
        XCTAssertEqual(row["version_source"], "dpkg_status")
        XCTAssertEqual(row["evidence_level"], "partial")
        XCTAssertEqual(row["static_evidence"], "dpkg_status")
        XCTAssertEqual(row["runtime_image_match"], "not_inferred")
        XCTAssertEqual(row["compatibility"], "profile_only_not_runtime_validation")
        XCTAssertEqual(row["filter_parsing"], "supported")
    }

    func testSubstrateAndSubstituteAndLibhookerAndSandyKeywordsMatch() {
        let packages = [
            package("mobilesubstrate", status: "install ok installed"),
            package("substrate", status: "install ok installed"),
            package("substitute", status: "install ok installed"),
            package("libhooker", status: "install ok installed"),
            package("sandy", status: "install ok installed")
        ]
        let rows = ReadOnlyDiagnosticsEngine.identifyInjectors(packages: packages, runtimeImages: [])
        let types = rows.compactMap { $0["type"] }
        XCTAssertEqual(types, ["substrate", "substrate", "substitute", "libhooker", "sandy"])
    }

    func testUnknownPackageProducesNoRow() {
        let rows = ReadOnlyDiagnosticsEngine.identifyInjectors(
            packages: [package("com.random.package", status: "install ok installed")], runtimeImages: [])
        XCTAssertTrue(rows.isEmpty)
    }

    func testMissingInstalledFlagIsNotMarkedInstalled() {
        let rows = ReadOnlyDiagnosticsEngine.identifyInjectors(
            packages: [package("ellekit", status: "deinstall ok config-files")], runtimeImages: [])
        XCTAssertEqual(rows.first?["installed"], "false")
    }

    func testRuntimeImageRowCarriesCurrentProcessScope() {
        let rows = ReadOnlyDiagnosticsEngine.identifyInjectors(
            packages: [],
            runtimeImages: [["type": "ellekit", "path": "/usr/lib/libellekit.dylib"]])
        XCTAssertEqual(rows.count, 1)
        let row = rows[0]
        XCTAssertEqual(row["image_path"], "/usr/lib/libellekit.dylib")
        XCTAssertEqual(row["runtime_evidence"], "current_process_image")
        XCTAssertEqual(row["scope"], "current_process_only")
    }

    func testEmptyPackagesAndImagesProduceNoRows() {
        XCTAssertTrue(ReadOnlyDiagnosticsEngine.identifyInjectors(packages: [], runtimeImages: []).isEmpty)
    }

    func testInjectorProfileCapabilityFlags() {
        let ellekit = ReadOnlyDiagnosticsEngine.injectorProfile("ellekit")
        XCTAssertEqual(ellekit.filterParsing, "supported")
        XCTAssertEqual(ellekit.appTargeting, "supported")
        XCTAssertEqual(ellekit.globalInjection, "supported")

        let substrate = ReadOnlyDiagnosticsEngine.injectorProfile("substrate")
        XCTAssertEqual(substrate.filterParsing, "unsupported")
        XCTAssertEqual(substrate.appTargeting, "supported")

        let unknown = ReadOnlyDiagnosticsEngine.injectorProfile("unknown")
        XCTAssertEqual(unknown.filterParsing, "unknown")
        XCTAssertEqual(unknown.appTargeting, "unknown")
        XCTAssertEqual(unknown.globalInjection, "unknown")
    }
}
