//
//  PluginDataFoundationTests.swift
//  FilterKit 0.1-E1 Plugin Data Foundation 离线测试
//
//  纯内存夹具：FKDiagnosticReport 扁平行 → PluginSnapshot / Repository。
//  不访问文件系统、不触发真实目录枚举；Repository 一次扫描缓存口径单独断言。
//
//  覆盖规格 §8：
//  1. 配对有效插件（exactMatch，三态独立，App 反向索引）；
//  2. 孤立 plist：installed unknown，configured confirmed；
//  3. 损坏 plist：installed confirmed，configured unverified；
//  4. 仅有 dylib：configured absent；
//  5. 全局规则 globalRule，不计入精确关联；
//  6. 未匹配目标 unmatchedTarget；
//  7. 无效配置 invalidConfiguration；
//  8. 三态独立：configured confirmed 时 loaded 仍 unknown；
//  9. 空报告无合成条目；
//  10. 快照共享：refresh 一次，后续读取不二次扫描；
//  11. 原始证据保留在 raw。
//

import Foundation
import XCTest
@testable import Core

final class PluginDataFoundationTests: XCTestCase {

    // MARK: - 夹具

    private func makeReport() -> FKDiagnosticReport {
        let plugins: [[String: String]] = [
            [
                "name": "ExampleTweak.dylib",
                "path": "/jb/ellekit/ExampleTweak.dylib",
                "exists": "true",
                "readable": "true",
                "size": "12345",
                "source": "dpkg_sileo",
                "loaded": "unknown",
                "package_owners": "com.example.tweak",
                "exact_package_record": "true"
            ],
            [
                "name": "Broken.dylib",
                "path": "/jb/ellekit/Broken.dylib",
                "exists": "true",
                "readable": "true",
                "size": "2048",
                "source": "unknown",
                "loaded": "unknown"
            ],
            [
                "name": "DylibOnly.dylib",
                "path": "/jb/ellekit/DylibOnly.dylib",
                "exists": "true",
                "readable": "true",
                "size": "100",
                "source": "manual",
                "loaded": "unknown"
            ]
        ]

        let filters: [[String: String]] = [
            [
                "plugin": "ExampleTweak",
                "dylib_match": "ExampleTweak.dylib",
                "plist_path": "/jb/ellekit/ExampleTweak.plist",
                "read_status": "readable",
                "parse_status": "parsed",
                "bundles": "com.example.app",
                "executables": "",
                "classes": "",
                "other_keys": "",
                "global": "false",
                "valid": "true",
                "matched_bundle_ids": "com.example.app"
            ],
            [
                "plugin": "Orphan",
                "plist_path": "/jb/ellekit/Orphan.plist",
                "read_status": "readable",
                "parse_status": "parsed",
                "bundles": "com.orphan.app",
                "global": "false",
                "valid": "true"
            ],
            [
                "plugin": "Broken",
                "plist_path": "/jb/ellekit/Broken.plist",
                "read_status": "read_failed",
                "parse_status": "read_failed",
                "valid": "false",
                "error": "read_failed"
            ],
            [
                "plugin": "Global",
                "plist_path": "/jb/ellekit/Global.plist",
                "global": "true",
                "valid": "true"
            ],
            [
                "plugin": "Unmatched",
                "plist_path": "/jb/ellekit/Unmatched.plist",
                "bundles": "com.nope",
                "unmatched_bundle_ids": "com.nope",
                "global": "false",
                "valid": "true"
            ],
            [
                "plugin": "Invalid",
                "plist_path": "/jb/ellekit/Invalid.plist",
                "parse_status": "not_parsed",
                "valid": "false"
            ]
        ]

        let associations: [[String: String]] = [
            [
                "plugin": "ExampleTweak",
                "bundle_id": "com.example.app",
                "match_type": "bundle",
                "category": "exact_match",
                "is_global": "false",
                "matched_app_count": "1",
                "unmatched_target_count": "0",
                "evidence": "static_filter_match_only",
                "loaded": "unknown"
            ],
            [
                "plugin": "Global",
                "bundle_id": "",
                "match_type": "none",
                "category": "global",
                "is_global": "true",
                "matched_app_count": "0",
                "unmatched_target_count": "0",
                "evidence": "static_filter_match_only",
                "loaded": "unknown"
            ],
            [
                "plugin": "Unmatched",
                "bundle_id": "com.nope",
                "match_type": "none",
                "category": "unmatched_target",
                "is_global": "false",
                "matched_app_count": "0",
                "unmatched_target_count": "1",
                "evidence": "static_filter_match_only",
                "loaded": "unknown"
            ],
            [
                "plugin": "Invalid",
                "bundle_id": "",
                "match_type": "none",
                "category": "invalid_configuration",
                "is_global": "false",
                "matched_app_count": "0",
                "unmatched_target_count": "0",
                "evidence": "static_filter_match_only",
                "loaded": "unknown"
            ]
        ]

        let applications: [[String: String]] = [
            [
                "bundle_id": "com.example.app",
                "name": "App A",
                "version": "1.0",
                "executable": "App",
                "is_system": "false"
            ]
        ]

        return FKDiagnosticReport(
            generatedAt: Date(timeIntervalSince1970: 1_763_600_000),
            environment: ["jailbreak": "roothide"],
            roots: [],
            dynamicLibraryDirectories: [],
            plugins: plugins,
            filters: filters,
            injectorEvidence: [],
            packages: [],
            fileOwnership: [],
            integrity: [],
            helperCandidates: [],
            helperRegistrations: [],
            applications: applications,
            associations: associations,
            findings: []
        )
    }

    private func plugin(namedBase base: String, in snapshot: PluginSnapshot) -> FKPlugin? {
        // ID 口径（E1 规格 §模型）：优先 `packageIdentifier:base`；无包标识回退 dylib
        // 基名；孤立 plist 为 `filter:base`。三种形态均需可被查找助手命中。
        snapshot.plugins.first {
            $0.id.lowercased().hasSuffix(":\(base)")
                || $0.id == "filter:\(base)"
                || $0.id == base
        }
    }

    // MARK: - 用例

    func testValidPairedPluginMapsConfirmedTripleWithExactAssociation() {
        let snapshot = PluginDataMapper.mapSnapshot(report: makeReport())
        guard let plugin = plugin(namedBase: "exampletweak", in: snapshot) else {
            return XCTFail("缺少 ExampleTweak 插件")
        }

        XCTAssertEqual(plugin.status.installed, .confirmed)
        XCTAssertEqual(plugin.status.configured, .confirmed)
        // 三态独立：configured confirmed 不得把 loaded 升级为 confirmed
        XCTAssertEqual(plugin.status.loaded, .unknown)
        XCTAssertEqual(plugin.fileSize, 12345)
        XCTAssertEqual(plugin.packageIdentifier, "com.example.tweak")
        XCTAssertEqual(plugin.configuration?.bundles, ["com.example.app"])
        XCTAssertEqual(plugin.configuration?.isGlobalRule, false)

        XCTAssertEqual(plugin.associations.count, 1)
        XCTAssertEqual(plugin.associations.first?.type, .exactMatch)

        // App 反向索引
        guard let app = snapshot.applicationByID["com.example.app"] else {
            return XCTFail("缺少 App A")
        }
        XCTAssertTrue(app.associatedPluginIDs.contains(plugin.id))
    }

    func testOrphanPlistInstalledUnknownConfiguredConfirmed() {
        let snapshot = PluginDataMapper.mapSnapshot(report: makeReport())
        guard let orphan = plugin(namedBase: "orphan", in: snapshot) else {
            return XCTFail("缺少孤立 plist")
        }
        XCTAssertEqual(orphan.status.installed, .unknown)
        XCTAssertEqual(orphan.status.configured, .confirmed)
        XCTAssertEqual(orphan.status.loaded, .unknown)
        XCTAssertNil(orphan.dylibPath)
        XCTAssertNotNil(orphan.configuration?.filterPath)
    }

    func testBrokenPlistInstalledConfirmedConfiguredUnverified() {
        let snapshot = PluginDataMapper.mapSnapshot(report: makeReport())
        guard let broken = plugin(namedBase: "broken", in: snapshot) else {
            return XCTFail("缺少 Broken 插件")
        }
        XCTAssertEqual(broken.status.installed, .confirmed)
        XCTAssertEqual(broken.status.configured, .unverified)
        XCTAssertEqual(broken.status.loaded, .unknown)
        XCTAssertEqual(broken.configuration?.parseStatus, "read_failed")
    }

    func testDylibOnlyConfiguredAbsent() {
        let snapshot = PluginDataMapper.mapSnapshot(report: makeReport())
        guard let only = plugin(namedBase: "dylibonly", in: snapshot) else {
            return XCTFail("缺少 DylibOnly 插件")
        }
        XCTAssertEqual(only.status.installed, .confirmed)
        XCTAssertEqual(only.status.configured, .absent)
        XCTAssertEqual(only.status.loaded, .unknown)
        XCTAssertNil(only.configuration)
    }

    func testAssociationTypeMappingGlobalUnmatchedInvalid() {
        let snapshot = PluginDataMapper.mapSnapshot(report: makeReport())

        let global = snapshot.associations.first { $0.pluginID.hasSuffix("global") }
        XCTAssertEqual(global?.type, .globalRule)
        XCTAssertEqual(global?.isGlobal, true)

        let unmatched = snapshot.associations.first { $0.pluginID.hasSuffix("unmatched") }
        XCTAssertEqual(unmatched?.type, .unmatchedTarget)
        XCTAssertEqual(unmatched?.matchType, "none")

        let invalid = snapshot.associations.first { $0.pluginID.hasSuffix("invalid") }
        XCTAssertEqual(invalid?.type, .invalidConfiguration)

        // 精确关联仅 1 条（ExampleTweak）
        let exact = snapshot.associations.filter { $0.type == .exactMatch }
        XCTAssertEqual(exact.count, 1)
    }

    func testLoadedStateAlwaysUnknownAcrossAllPlugins() {
        let snapshot = PluginDataMapper.mapSnapshot(report: makeReport())
        for plugin in snapshot.plugins {
            XCTAssertEqual(plugin.status.loaded, .unknown)
        }
        for association in snapshot.associations {
            XCTAssertEqual(association.loaded, "unknown")
        }
    }

    func testEmptyReportProducesNoSyntheticItems() {
        let empty = FKDiagnosticReport(
            generatedAt: Date(),
            environment: [:],
            roots: [], dynamicLibraryDirectories: [],
            plugins: [], filters: [], injectorEvidence: [], packages: [],
            fileOwnership: [], integrity: [], helperCandidates: [],
            helperRegistrations: [], applications: [], associations: [],
            findings: []
        )
        let snapshot = PluginDataMapper.mapSnapshot(report: empty)
        XCTAssertTrue(snapshot.plugins.isEmpty)
        XCTAssertTrue(snapshot.applications.isEmpty)
        XCTAssertTrue(snapshot.associations.isEmpty)
        XCTAssertTrue(snapshot.pluginByID.isEmpty)
        XCTAssertTrue(snapshot.applicationByID.isEmpty)
    }

    func testRepositoryCachesSingleScanForAllReads() {
        let repository = DiagnosticPluginRepository(engine: ReadOnlyDiagnosticsEngine())
        XCTAssertNil(repository.currentSnapshot())
        XCTAssertTrue(repository.applications().isEmpty)

        let snapshot = repository.refresh()
        XCTAssertEqual(repository.refreshCount, 1)
        XCTAssertNotNil(repository.currentSnapshot())

        // 后续读取命中缓存，不触发二次扫描
        _ = repository.plugin(id: snapshot.plugins.first?.id ?? "")
        _ = repository.applications()
        _ = repository.currentSnapshot()
        XCTAssertEqual(repository.refreshCount, 1)
    }

    func testRawEvidenceRetainedOnPluginRecord() {
        let snapshot = PluginDataMapper.mapSnapshot(report: makeReport())
        guard let plugin = plugin(namedBase: "exampletweak", in: snapshot) else {
            return XCTFail("缺少 ExampleTweak 插件")
        }
        XCTAssertEqual(plugin.raw["source"], "dpkg_sileo")
        XCTAssertEqual(plugin.raw["package_owners"], "com.example.tweak")
        XCTAssertEqual(plugin.source.packageOwners, ["com.example.tweak"])
        XCTAssertTrue(plugin.source.exactPackageRecord)
    }
}
