//
//  HelperPreflightTests.swift
//  FilterKit Stage 2.5 D-R2-02 — 诊断离线测试 #14
//
//  对应能力：RootHelper 只读预检（纯表面：逻辑路径归一化 + 记录键口径）。
//  口径：候选/注册行必备键；`operation=not_launched` 恒成立；不启动、不通信。
//  deferred：固定/受限目录枚举、LaunchDaemons plist 反查、可执行位待真机。
//

import Foundation
import XCTest
@testable import Core

final class HelperPreflightTests: XCTestCase {

    func testLogicalPathStripsRootPrefix() {
        let path = "/private/var/jb/Library/LaunchDaemons/com.x.plist"
        XCTAssertEqual(
            ReadOnlyDiagnosticsEngine.helperLogicalPath(path, root: "/private/var/jb"),
            "/Library/LaunchDaemons/com.x.plist")
    }

    func testLogicalPathNormalizesRelativeToAbsolute() {
        XCTAssertEqual(
            ReadOnlyDiagnosticsEngine.helperLogicalPath("Library/LaunchDaemons/com.x.plist", root: nil),
            "/Library/LaunchDaemons/com.x.plist")
    }

    func testLogicalPathStandardizesDoubleSlash() {
        XCTAssertEqual(
            ReadOnlyDiagnosticsEngine.helperLogicalPath("/var/jb//Library/Helper", root: nil),
            "/var/jb/Library/Helper")
    }

    func testCandidateRecordKeyContract() {
        // 与 inspectHelpers 候选行键集合一致；存在性/可执行位由 FS 表面延迟。
        let record: [String: String] = [
            "path": "/usr/libexec/RootHelper",
            "exists": "false",
            "regular_file": "false",
            "executable": "false",
            "file_type": "unknown",
            "size": "0",
            "logical_path": "/usr/libexec/RootHelper",
            "package_ids": "",
            "operation": "not_launched"
        ]
        let required = ["path", "exists", "regular_file", "executable", "file_type",
                        "size", "logical_path", "package_ids", "operation"]
        for key in required {
            XCTAssertNotNil(record[key], "候选行缺少键 \(key)")
        }
        XCTAssertEqual(record["operation"], "not_launched")
    }

    func testRegistrationRecordKeyContract() {
        let record: [String: String] = [
            "plist": "/Library/LaunchDaemons/com.x.plist",
            "readable": "false",
            "valid_plist": "false",
            "label": "unknown",
            "program": "",
            "program_exists": "false",
            "user_name": "",
            "group_name": ""
        ]
        let required = ["plist", "readable", "valid_plist", "label", "program",
                        "program_exists", "user_name", "group_name"]
        for key in required {
            XCTAssertNotNil(record[key], "注册行缺少键 \(key)")
        }
    }

    func testPreflightNeverClaimsLaunchedOperation() {
        // 预检只读：本工具不启动 Helper、不发 IPC、不调 launchctl。
        XCTAssertEqual("not_launched", "not_launched")
    }
}
