//
//  FileSourceTests.swift
//  FilterKit Stage 2.5 D-R2-02 — 诊断离线测试 #11
//
//  对应能力：插件来源识别（纯函数：来源归类）。
//  口径：有精确归属 → dpkg；status 在场无精确归属 → manual_inferred；
//  status 缺失无归属 → unknown；推断来源不冒充真实清单。
//  deferred：真机 dpkg 清单对照待 G12 门禁。
//

import Foundation
import XCTest
@testable import Core

final class FileSourceTests: XCTestCase {

    func testExactDpkgOwnerIsDpkgSource() {
        let result = ReadOnlyDiagnosticsEngine.classifyPluginSource(
            owners: ["com.a"], dpkgStatusPresent: true)
        XCTAssertEqual(result.source, "dpkg")
        XCTAssertEqual(result.sourceEvidence, "dpkg_list_exact_path")
        XCTAssertEqual(result.exactRecord, "true")
    }

    func testMultipleOwnersStillExactRecord() {
        let result = ReadOnlyDiagnosticsEngine.classifyPluginSource(
            owners: ["com.a", "com.b"], dpkgStatusPresent: true)
        XCTAssertEqual(result.source, "dpkg")
        XCTAssertEqual(result.exactRecord, "true")
    }

    func testNoOwnerButStatusPresentIsManualInferred() {
        let result = ReadOnlyDiagnosticsEngine.classifyPluginSource(
            owners: [], dpkgStatusPresent: true)
        XCTAssertEqual(result.source, "manual_inferred")
        XCTAssertEqual(result.sourceEvidence, "no_exact_dpkg_list_owner")
        XCTAssertEqual(result.exactRecord, "false")
    }

    func testNoOwnerAndNoStatusIsUnknown() {
        let result = ReadOnlyDiagnosticsEngine.classifyPluginSource(
            owners: [], dpkgStatusPresent: false)
        XCTAssertEqual(result.source, "unknown")
        XCTAssertEqual(result.sourceEvidence, "insufficient")
        XCTAssertEqual(result.exactRecord, "false")
    }

    func testInferredSourceDoesNotClaimExactRecord() {
        let inferred = ReadOnlyDiagnosticsEngine.classifyPluginSource(
            owners: [], dpkgStatusPresent: true)
        XCTAssertNotEqual(inferred.exactRecord, "true")
    }
}
