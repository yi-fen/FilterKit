//
//  PackageMetadataTests.swift
//  FilterKit Stage 2.5 D-R2-02 — 诊断离线测试 #9
//
//  对应能力：包元数据提取（纯函数：`dpkgState` 状态机）。
//  口径：`install ok installed` → installed；`reinstreq`；installed 非标准状态；
//  已知中间态；缺字段空串。字段大小写不敏感首现拼写由 status 解析器覆盖（#7）。
//  deferred：全字段 `raw_fields` 保留待结构化模型轮。
//

import Foundation
import XCTest
@testable import Core

final class PackageMetadataTests: XCTestCase {

    func testStandardInstalledState() {
        let state = ReadOnlyDiagnosticsEngine.dpkgState("install ok installed")
        XCTAssertEqual(state.want, "install")
        XCTAssertEqual(state.errorFlag, "ok")
        XCTAssertEqual(state.current, "installed")
        XCTAssertEqual(state.state, "installed")
    }

    func testReinstreqFlagOverridesInstalledCurrent() {
        let state = ReadOnlyDiagnosticsEngine.dpkgState("hold reinstreq installed")
        XCTAssertEqual(state.state, "reinstreq")
    }

    func testInstalledWithNonStandardWantIsNonstandardStatus() {
        let state = ReadOnlyDiagnosticsEngine.dpkgState("deinstall ok installed")
        XCTAssertEqual(state.current, "installed")
        XCTAssertEqual(state.state, "installed_nonstandard_status")
    }

    func testKnownIntermediateStatesAreRecognized() {
        XCTAssertEqual(ReadOnlyDiagnosticsEngine.dpkgState("install ok unpacked").state, "unpacked")
        XCTAssertEqual(ReadOnlyDiagnosticsEngine.dpkgState("install ok half-installed").state, "half-installed")
        XCTAssertEqual(ReadOnlyDiagnosticsEngine.dpkgState("install ok half-configured").state, "half-configured")
        XCTAssertEqual(ReadOnlyDiagnosticsEngine.dpkgState("install ok config-files").state, "config-files")
        XCTAssertEqual(ReadOnlyDiagnosticsEngine.dpkgState("remove ok not-installed").state, "not-installed")
        XCTAssertEqual(ReadOnlyDiagnosticsEngine.dpkgState("install ok triggers-awaited").state, "triggers-awaited")
        XCTAssertEqual(ReadOnlyDiagnosticsEngine.dpkgState("install ok triggers-pending").state, "triggers-pending")
    }

    func testEmptyStatusDefaultsToUnknown() {
        let state = ReadOnlyDiagnosticsEngine.dpkgState("")
        XCTAssertEqual(state.want, "unknown")
        XCTAssertEqual(state.errorFlag, "unknown")
        XCTAssertEqual(state.current, "unknown")
        XCTAssertEqual(state.state, "unknown")
    }

    func testFourPartsFallsBackToCurrentState() {
        // parts.count ≠ 3 时 state = current，不做非标准再分类。
        let state = ReadOnlyDiagnosticsEngine.dpkgState("install ok installed extra")
        XCTAssertEqual(state.current, "installed")
        XCTAssertEqual(state.state, "installed")
    }
}
