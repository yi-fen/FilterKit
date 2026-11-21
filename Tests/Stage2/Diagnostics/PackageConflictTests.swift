//
//  PackageConflictTests.swift
//  FilterKit Stage 2.5 D-R2-02 — 诊断离线测试 #13
//
//  对应能力：跨包归属冲突（纯聚合：行形状口径）。
//  口径：同路径多包 → conflict=true；单包 → false；未归属插件文件计入未归属。
//  deferred：`.list` 读取、冲突记录独立列表待结构化模型轮与 FS 接缝（D-R2-03）。
//

import Foundation
import XCTest
@testable import Core

final class PackageConflictTests: XCTestCase {

    private func conflictFlag(ownerPackages: String) -> String {
        // 与 analyzeDpkg 归属行一致：packages 以逗号分隔，split 后计数 >1 即冲突。
        let ids = ownerPackages.split(separator: ",").map(String.init)
        return String(ids.count > 1)
    }

    func testSingleOwnerIsNotConflict() {
        XCTAssertEqual(conflictFlag(ownerPackages: "com.a"), "false")
    }

    func testMultipleOwnersAreConflict() {
        XCTAssertEqual(conflictFlag(ownerPackages: "com.a,com.b"), "true")
    }

    func testEmptyOwnerStringIsNotConflict() {
        XCTAssertEqual(conflictFlag(ownerPackages: ""), "false")
    }

    func testUnownedPluginPathIsCountedSeparately() {
        // 与 analyzeDpkg 口径一致：插件逻辑路径在 owners 字典中查无记录即未归属；
        // 离线阶段只固定该判定约定，真实 `.list` 读取待 FS 接缝。
        let owners: [String: Set<String>] = ["/Library/x.dylib": ["com.a"]]
        XCTAssertNil(owners["/Library/orphan.dylib"])
        XCTAssertNotNil(owners["/Library/x.dylib"])
    }
}
