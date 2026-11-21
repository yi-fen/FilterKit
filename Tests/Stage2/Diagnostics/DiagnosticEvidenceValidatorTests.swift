//
//  DiagnosticEvidenceValidatorTests.swift
//  FilterKit Stage 2.6 R3-A9 — E-01～E-09 证据一致性离线测试（D-R2-04）
//
//  每条规则独立用例；校验器为内部纯函数，不触碰公共 Models 与报告信封。
//  合规基线三元组 / 段记录不产生违规。
//

import Foundation
import XCTest
@testable import Core

final class DiagnosticEvidenceValidatorTests: XCTestCase {

    // MARK: E-01 installed 不自动推导 configured

    func testE01ConfiguredNotPromotedFromInstalledOnly() {
        let installed = DiagnosticEvidence(level: .confirmed, source: "dpkg_status", observedValue: "com.a")
        let configured = DiagnosticEvidence(level: .confirmed, source: "derived_from_installed")
        let loaded = DiagnosticEvidence(level: .unknown, source: "insufficient")
        let violations = DiagnosticEvidenceValidator.validateTriple(
            installed: installed, configured: configured, loaded: loaded)
        XCTAssertTrue(violations.contains { $0.rule == "E-01" })
    }

    // MARK: E-02 configured 不自动推导 loaded

    func testE02LoadedConfirmedWithoutConfirmedConfigurationViolates() {
        let installed = DiagnosticEvidence(level: .confirmed, source: "dpkg_status")
        let configured = DiagnosticEvidence(level: .unknown, source: "insufficient")
        let loaded = DiagnosticEvidence(level: .confirmed, source: "runtime_image")
        let violations = DiagnosticEvidenceValidator.validateTriple(
            installed: installed, configured: configured, loaded: loaded)
        XCTAssertTrue(violations.contains { $0.rule == "E-02" })
    }

    // MARK: E-03 静态匹配不能证明 loaded

    func testE03StaticMatchCannotConfirmLoaded() {
        let installed = DiagnosticEvidence(level: .confirmed, source: "dpkg_status")
        let configured = DiagnosticEvidence(level: .confirmed, source: "dpkg_status")
        let loaded = DiagnosticEvidence(level: .confirmed, source: "static_filesystem")
        let violations = DiagnosticEvidenceValidator.validateTriple(
            installed: installed, configured: configured, loaded: loaded)
        XCTAssertTrue(violations.contains { $0.rule == "E-03" })
    }

    // MARK: E-04 缺少 MD5 不证明文件损坏

    func testE04MissingChecksumRecordNotMarkedCorrupted() {
        let rows: [[String: String]] = [
            ["status": "no_checksum_record", "disposition": "hard_failure"]
        ]
        let violations = DiagnosticEvidenceValidator.validateIntegrity(rows)
        XCTAssertEqual(violations.map { $0.rule }, ["E-04"])
    }

    func testE04CompliantNoChecksumRecordPasses() {
        let rows: [[String: String]] = [
            ["status": "no_checksum_record", "disposition": "not_confirmed"]
        ]
        XCTAssertTrue(DiagnosticEvidenceValidator.validateIntegrity(rows).isEmpty)
    }

    // MARK: E-05 不可访问不等于不存在

    func testE05PermissionDeniedNotRecordedAsNotFound() {
        let rows: [[String: String]] = [
            ["status": "not_found", "error": "permission denied", "exists": "false"]
        ]
        let violations = DiagnosticEvidenceValidator.validateAccessRecords(rows)
        XCTAssertEqual(violations.map { $0.rule }, ["E-05"])
    }

    func testE05CompliantNotFoundPasses() {
        let rows: [[String: String]] = [
            ["status": "not_found", "exists": "false"]
        ]
        XCTAssertTrue(DiagnosticEvidenceValidator.validateAccessRecords(rows).isEmpty)
    }

    // MARK: E-06 未知注入器不自动标记不兼容

    func testE06UnknownInjectorNotMarkedIncompatible() {
        let rows: [[String: String]] = [
            ["type": "unknown", "compatibility": "incompatible"]
        ]
        let violations = DiagnosticEvidenceValidator.validateInjectors(rows)
        XCTAssertEqual(violations.map { $0.rule }, ["E-06"])
    }

    // MARK: E-07 global 不计入 exact_match

    func testE07GlobalNotCountedAsExactMatch() {
        let rows: [[String: String]] = [
            ["is_global": "true", "category": "exact_match"]
        ]
        let violations = DiagnosticEvidenceValidator.validateAssociations(rows)
        XCTAssertTrue(violations.contains { $0.rule == "E-07" })
    }

    // MARK: E-08 缺运行时证据不报成功关联

    func testE08StaticAssociationMustNotReportLoadedSuccess() {
        let rows: [[String: String]] = [
            ["evidence": "static_filter_match_only", "loaded": "false"]
        ]
        let violations = DiagnosticEvidenceValidator.validateAssociations(rows)
        XCTAssertTrue(violations.contains { $0.rule == "E-08" })
    }

    func testE08CompliantStaticAssociationPasses() {
        let rows: [[String: String]] = [
            ["evidence": "static_filter_match_only", "loaded": "unknown", "category": "unmatched_target"]
        ]
        XCTAssertTrue(DiagnosticEvidenceValidator.validateAssociations(rows).isEmpty)
    }

    // MARK: E-09 无运行时证据 loaded 保持 unknown

    func testE09LoadedRemainsUnknownWithoutRuntimeEvidence() {
        let installed = DiagnosticEvidence(level: .confirmed, source: "dpkg_status")
        let configured = DiagnosticEvidence(level: .confirmed, source: "dpkg_status")
        let loaded = DiagnosticEvidence(level: .inferred, source: "static_filesystem")
        let violations = DiagnosticEvidenceValidator.validateTriple(
            installed: installed, configured: configured, loaded: loaded)
        XCTAssertTrue(violations.contains { $0.rule == "E-09" })
    }

    func testCompliantRuntimeTripleProducesNoViolation() {
        let installed = DiagnosticEvidence(level: .confirmed, source: "dpkg_status")
        let configured = DiagnosticEvidence(level: .confirmed, source: "dpkg_status")
        let loaded = DiagnosticEvidence(level: .confirmed, source: "runtime_image")
        let violations = DiagnosticEvidenceValidator.validateTriple(
            installed: installed, configured: configured, loaded: loaded)
        XCTAssertTrue(violations.isEmpty)
    }
}
