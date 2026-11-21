//
//  DiagnosticsExportBridgeTests.swift
//  FilterKit Stage 2 — R3-C Live Diagnostics Export Bridge（路线 A）
//
//  覆盖冻结口径：
//  1. 完成态报告全类别映射，原始键值完整保留；
//  2. 空报告记 completed + 空条目，与失败态区分；
//  3. 未扫描段为空条目，不生成合成插件；
//  4. 失败段保留上一次成功时间用于追溯，不冒充本次结果；
//  5. 重复扫描后段以最新结果为准；
//  6. 合并 JSON 编码/解码后诊断段字段一致；
//  7. 既有信封字段在合并导出中保持兼容、不被覆盖；
//  8. loaded=unknown 往返后仍为 unknown。
//
//  本文件不访问文件系统、不触发引擎扫描；夹具为纯内存报告。
//

import Foundation
import XCTest
@testable import Core
@testable import Models

final class DiagnosticsExportBridgeTests: XCTestCase {

    // MARK: - 夹具

    private func makeReport(generatedAt: Date,
                            roots: [[String: String]] = [],
                            plugins: [[String: String]] = [],
                            filters: [[String: String]] = [],
                            findings: [FKDiagnosticFinding] = []) -> FKDiagnosticReport {
        FKDiagnosticReport(
            generatedAt: generatedAt,
            environment: ["os_version": "17.0.2", "scan_mode": "read_only"],
            roots: roots,
            dynamicLibraryDirectories: [],
            plugins: plugins,
            filters: filters,
            injectorEvidence: [],
            packages: [],
            fileOwnership: [],
            integrity: [],
            helperCandidates: [],
            helperRegistrations: [],
            applications: [],
            associations: [],
            findings: findings)
    }

    private func makeEnvelope() -> ReportEnvelope {
        ReportEnvelope(
            profile: ProfileRef(id: "test-profile", route: "roothide"),
            environment: JailbreakEnvironment(profileId: "test-profile"),
            plugins: [],
            unknownItems: [],
            warnings: [])
    }

    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    // MARK: - 1. 完成态全类别映射 + payload 不丢字段

    func testCompletedSectionMapsCategoriesAndPreservesPayload() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let report = makeReport(
            generatedAt: date,
            roots: [["path": "/private/var/jb", "status": "validated", "readable": "true"]],
            plugins: [["name": "PreviewTweak.dylib",
                      "path": "/private/var/jb/Library/TweakInject/PreviewTweak.dylib",
                      "source": "unknown",
                      "loaded": "unknown"]],
            filters: [["plugin": "PreviewTweak.dylib", "parse_status": "parsed", "bundles": "com.hide"]],
            findings: [FKDiagnosticFinding(id: "F1", title: "Sample finding", state: "unknown", detail: "detail",
                                           payload: ["key": "value"])])

        let section = DiagnosticsReportMapper.section(from: report)

        XCTAssertEqual(section.scanState, .completed)
        XCTAssertEqual(section.generatedAt, date)
        XCTAssertEqual(section.environment["os_version"], "17.0.2")

        let categories = Set(section.items.map { $0.category })
        XCTAssertTrue(categories.contains("roots"))
        XCTAssertTrue(categories.contains("plugins"))
        XCTAssertTrue(categories.contains("filters"))
        XCTAssertTrue(categories.contains("finding"))

        let pluginItem = try XCTUnwrap(section.items.first { $0.category == "plugins" })
        XCTAssertEqual(pluginItem.title, "PreviewTweak.dylib")
        // 原始行键值完整保留，未裁剪。
        XCTAssertEqual(pluginItem.payload["path"], "/private/var/jb/Library/TweakInject/PreviewTweak.dylib")
        XCTAssertEqual(pluginItem.payload["loaded"], "unknown")
        XCTAssertEqual(pluginItem.payload["source"], "unknown")

        let findingItem = try XCTUnwrap(section.items.first { $0.category == "finding" })
        XCTAssertEqual(findingItem.status, "unknown")
        XCTAssertEqual(findingItem.payload["key"], "value")
    }

    // MARK: - 2. 空报告 = completed 空条目

    func testEmptyReportMapsToCompletedEmptySection() {
        let report = makeReport(generatedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let section = DiagnosticsReportMapper.section(from: report)

        XCTAssertEqual(section.scanState, .completed)
        XCTAssertNotNil(section.generatedAt)
        XCTAssertTrue(section.items.isEmpty)
    }

    // MARK: - 3. 未扫描段无合成数据

    func testNeverRunSectionContainsNoSyntheticItems() {
        let section = DiagnosticsExportSection.neverRun()

        XCTAssertEqual(section.scanState, .neverRun)
        XCTAssertNil(section.generatedAt)
        XCTAssertTrue(section.items.isEmpty)
        XCTAssertTrue(section.environment.isEmpty)

        let syntheticNames = ["Preview Tweak", "Broken Plist", "Orphan Plist", "PreviewTweak.dylib"]
        for item in section.items {
            XCTAssertFalse(syntheticNames.contains(item.title))
        }
    }

    // MARK: - 4. 失败段追溯历史时间，不冒充本次结果

    func testFailedSectionKeepsPreviousTimeWithoutCurrentItems() {
        let previous = Date(timeIntervalSince1970: 1_700_000_000)
        let section = DiagnosticsExportSection.failed(previousCompletedAt: previous)

        XCTAssertEqual(section.scanState, .failed)
        XCTAssertNil(section.generatedAt)
        XCTAssertTrue(section.items.isEmpty)
        XCTAssertEqual(section.previousCompletedAt, previous)
    }

    // MARK: - 5. 重复扫描以最新结果为准

    func testRepeatedMappingUsesLatestReport() {
        let first = makeReport(generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
                               plugins: [["name": "first.dylib", "loaded": "unknown"]])
        let second = makeReport(generatedAt: Date(timeIntervalSince1970: 1_700_000_120),
                                plugins: [["name": "second.dylib", "loaded": "unknown"]])

        let firstSection = DiagnosticsReportMapper.section(from: first)
        let secondSection = DiagnosticsReportMapper.section(from: second)

        XCTAssertEqual(firstSection.items.first?.title, "first.dylib")
        XCTAssertEqual(secondSection.items.first?.title, "second.dylib")
        XCTAssertNotEqual(firstSection.generatedAt, secondSection.generatedAt)
    }

    // MARK: - 6. 合并 JSON 诊断段往返一致

    func testCombinedExportRoundTripsDiagnosticsSection() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let report = makeReport(generatedAt: date,
                                plugins: [["name": "roundtrip.dylib", "loaded": "unknown"]])
        let section = DiagnosticsReportMapper.section(from: report)

        let data = try CombinedReportEncoder().encode(envelope: makeEnvelope(), diagnostics: section)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let diagnosticsObject = try XCTUnwrap(object["diagnostics"])
        let diagnosticsData = try JSONSerialization.data(withJSONObject: diagnosticsObject)

        let decoded = try makeDecoder().decode(DiagnosticsExportSection.self, from: diagnosticsData)
        XCTAssertEqual(decoded, section)
    }

    // MARK: - 7. 信封字段兼容，诊断段为新增键

    func testCombinedExportPreservesEnvelopeFields() throws {
        let data = try CombinedReportEncoder().encode(envelope: makeEnvelope(), diagnostics: nil)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        for key in ["schemaVersion", "generatorVersion", "profile", "environment",
                    "plugins", "unknownItems", "warnings", "diagnostics"] {
            XCTAssertNotNil(object[key], "合并导出缺少顶层键 \(key)")
        }

        // 诊断段为 neverRun 空段，未扫描不带入插件。
        let diagnosticsObject = try XCTUnwrap(object["diagnostics"] as? [String: Any])
        XCTAssertEqual(diagnosticsObject["scanState"] as? String, "neverRun")
        XCTAssertTrue((diagnosticsObject["items"] as? [Any])?.isEmpty ?? false)
    }

    // MARK: - 8. loaded=unknown 往返保留

    func testLoadedUnknownSurvivesRoundTrip() throws {
        let report = makeReport(generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
                                plugins: [["name": "loaded.dylib", "loaded": "unknown"]])
        let section = DiagnosticsReportMapper.section(from: report)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(section)
        let decoded = try makeDecoder().decode(DiagnosticsExportSection.self, from: data)

        let pluginItem = try XCTUnwrap(decoded.items.first { $0.category == "plugins" })
        XCTAssertEqual(pluginItem.payload["loaded"], "unknown")
    }
}
