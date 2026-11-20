//
//  PermissionProbeStatusTests.swift
//  FilterKit Stage 2 — PermissionProbe D1（状态枚举口径）
//
//  覆盖规格 §5：六态原始值、Codable 往返、notExecuted 不计 failed、unknown 独立。
//  本机无 Swift 工具链，用例在 macOS runner 执行。
//

import Foundation
import XCTest
@testable import Models

final class PermissionProbeStatusTests: XCTestCase {

    func testRawValues() {
        XCTAssertEqual(ProbeStatus.passed.rawValue, "passed")
        XCTAssertEqual(ProbeStatus.failed.rawValue, "failed")
        XCTAssertEqual(ProbeStatus.permissionDenied.rawValue, "permission_denied")
        XCTAssertEqual(ProbeStatus.unavailable.rawValue, "unavailable")
        XCTAssertEqual(ProbeStatus.notExecuted.rawValue, "not_executed")
        XCTAssertEqual(ProbeStatus.unknown.rawValue, "unknown")
    }

    func testAllStatusesRoundTrip() throws {
        let statuses: [ProbeStatus] = [
            .passed, .failed, .permissionDenied,
            .unavailable, .notExecuted, .unknown
        ]
        for status in statuses {
            let data = try JSONEncoder().encode(status)
            let decoded = try JSONDecoder().decode(ProbeStatus.self, from: data)
            XCTAssertEqual(decoded, status)
        }
    }

    func testNotExecutedIsNotFailed() {
        XCTAssertNotEqual(ProbeStatus.notExecuted, ProbeStatus.failed)
        XCTAssertNotEqual(ProbeStatus.notExecuted, ProbeStatus.passed)
    }

    func testUnknownIsIndependentFromPassedAndFailed() {
        XCTAssertNotEqual(ProbeStatus.unknown, ProbeStatus.passed)
        XCTAssertNotEqual(ProbeStatus.unknown, ProbeStatus.failed)
        XCTAssertNotEqual(ProbeStatus.unknown, ProbeStatus.permissionDenied)
    }
}
