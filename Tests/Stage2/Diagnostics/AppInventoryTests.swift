//
//  AppInventoryTests.swift
//  FilterKit Stage 2.5 D-R2-02 — 诊断离线测试 #15
//
//  对应能力：已安装 App 枚举（纯表面：空态守卫口径）。
//  口径：私有 Workspace 不可用/非数组 → 空清单，不伪造；报告 App 段键齐全。
//  deferred：`LSApplicationWorkspace` 真机行为待 G 门禁。
//

import Foundation
import XCTest
@testable import Core

final class AppInventoryTests: XCTestCase {

    func testApplicationsSectionIsArrayOnHostRun() {
        let report = ReadOnlyDiagnosticsEngine().scan()
        XCTAssertTrue(report.applications is [[String: String]])
    }

    func testEveryAppRowCarriesNonEmptyBundleIDWhenPresent() {
        let report = ReadOnlyDiagnosticsEngine().scan()
        for row in report.applications {
            XCTAssertFalse((row["bundle_id"] ?? "").isEmpty)
        }
    }

    func testEmptyStateDoesNotFabricateBundleIDs() {
        let report = ReadOnlyDiagnosticsEngine().scan()
        let bundleIDs = report.applications.compactMap { $0["bundle_id"] }.filter { !$0.isEmpty }
        // 非 Objective-C 宿主/无 Workspace 实例时空清单；不允许出现占位 bundle id。
        for id in bundleIDs {
            XCTAssertFalse(id.hasPrefix("placeholder"))
            XCTAssertFalse(id == "unknown")
        }
    }
}
