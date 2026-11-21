//
//  PluginListQueryTests.swift
//  FilterKit 0.1-E2 Plugin List & Discovery 离线测试
//
//  纯内存夹具：E1 快照 → 投影条目 → 查询引擎。不访问文件系统、不触发真实目录
//  枚举；E2-16 验证搜索/筛选不增加 Repository 扫描次数。
//
//  覆盖规格 §5 矩阵 E2-01 ～ E2-16。
//

import Foundation
import XCTest
@testable import Core

final class PluginListQueryTests: XCTestCase {

    private let engine = PluginListQueryEngine()

    // MARK: - 夹具（经 E1 映射链路构造快照）

    private func makeReport() -> FKDiagnosticReport {
        let plugins: [[String: String]] = [
            [
                "name": "Alpha Tweak.dylib",
                "path": "/jb/ellekit/Alpha Tweak.dylib",
                "exists": "true", "readable": "true", "size": "100",
                "source": "dpkg_sileo", "loaded": "unknown",
                "package_owners": "com.alpha.tweak"
            ],
            [
                "name": "beta-plugin.dylib",
                "path": "/jb/ellekit/beta-plugin.dylib",
                "exists": "true", "readable": "true", "size": "200",
                "source": "manual", "loaded": "unknown"
            ],
            [
                "name": "Gamma Broken.dylib",
                "path": "/jb/ellekit/Gamma Broken.dylib",
                "exists": "true", "readable": "true", "size": "300",
                "source": "unknown", "loaded": "unknown"
            ],
            [
                "name": "Echo Unmatched.dylib",
                "path": "/jb/ellekit/Echo Unmatched.dylib",
                "exists": "true", "readable": "true", "size": "400",
                "source": "unknown", "loaded": "unknown"
            ],
            [
                "name": "Zeta Missing.dylib",
                "path": "/jb/ellekit/Zeta Missing.dylib",
                "exists": "false", "readable": "false",
                "source": "unknown", "loaded": "unknown"
            ]
        ]

        let filters: [[String: String]] = [
            [
                "plugin": "Alpha Tweak",
                "plist_path": "/jb/ellekit/Alpha Tweak.plist",
                "read_status": "readable", "parse_status": "parsed",
                "bundles": "com.alpha.app", "global": "false", "valid": "true"
            ],
            [
                "plugin": "Gamma Broken",
                "plist_path": "/jb/ellekit/Gamma Broken.plist",
                "read_status": "read_failed", "parse_status": "read_failed",
                "valid": "false"
            ],
            [
                "plugin": "Delta Orphan",
                "plist_path": "/jb/ellekit/Delta Orphan.plist",
                "read_status": "readable", "parse_status": "parsed",
                "bundles": "com.delta.app", "global": "true", "valid": "true"
            ],
            [
                "plugin": "Echo Unmatched",
                "plist_path": "/jb/ellekit/Echo Unmatched.plist",
                "bundles": "com.echo.nope", "unmatched_bundle_ids": "com.echo.nope",
                "global": "false", "valid": "true"
            ]
        ]

        let associations: [[String: String]] = [
            [
                "plugin": "Alpha Tweak", "bundle_id": "com.alpha.app",
                "match_type": "bundle", "category": "exact_match",
                "is_global": "false", "matched_app_count": "1",
                "unmatched_target_count": "0", "evidence": "static_filter_match_only",
                "loaded": "unknown"
            ],
            [
                "plugin": "Delta Orphan", "bundle_id": "",
                "match_type": "none", "category": "global",
                "is_global": "true", "matched_app_count": "0",
                "unmatched_target_count": "0", "evidence": "static_filter_match_only",
                "loaded": "unknown"
            ],
            [
                "plugin": "Gamma Broken", "bundle_id": "",
                "match_type": "none", "category": "invalid_configuration",
                "is_global": "false", "matched_app_count": "0",
                "unmatched_target_count": "0", "evidence": "static_filter_match_only",
                "loaded": "unknown"
            ],
            [
                "plugin": "Echo Unmatched", "bundle_id": "com.echo.nope",
                "match_type": "none", "category": "unmatched_target",
                "is_global": "false", "matched_app_count": "0",
                "unmatched_target_count": "1", "evidence": "static_filter_match_only",
                "loaded": "unknown"
            ]
        ]

        let applications: [[String: String]] = [
            ["bundle_id": "com.alpha.app", "name": "Alpha App", "is_system": "false"]
        ]

        return FKDiagnosticReport(
            generatedAt: Date(timeIntervalSince1970: 1_763_600_000),
            environment: ["jailbreak": "roothide"],
            roots: [], dynamicLibraryDirectories: [],
            plugins: plugins, filters: filters, injectorEvidence: [],
            packages: [], fileOwnership: [], integrity: [],
            helperCandidates: [], helperRegistrations: [],
            applications: applications, associations: associations, findings: []
        )
    }

    private func makeEntries() -> [PluginListEntry] {
        let snapshot = PluginDataMapper.mapSnapshot(report: makeReport())
        return PluginListProjection.entries(from: snapshot.plugins)
    }

    // MARK: - E2-01 ～ E2-06 搜索

    func testE201EmptySearchReturnsAll() {
        let entries = makeEntries()
        let result = engine.execute(entries: entries, query: .empty)
        XCTAssertEqual(result.count, entries.count)
    }

    func testE202SearchByName() {
        let entries = makeEntries()
        let result = engine.execute(entries: entries,
                                    query: PluginListQuery(searchText: "Alpha Tweak"))
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.displayName, "Alpha Tweak.dylib")
    }

    func testE203SearchIsCaseInsensitive() {
        let entries = makeEntries()
        let result = engine.execute(entries: entries,
                                    query: PluginListQuery(searchText: "alpha"))
        XCTAssertEqual(result.count, 1)
    }

    func testE204SearchByDylibFileName() {
        let entries = makeEntries()
        let result = engine.execute(entries: entries,
                                    query: PluginListQuery(searchText: "beta-plugin"))
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.fileName, "beta-plugin.dylib")
    }

    func testE205SearchByPath() {
        let entries = makeEntries()
        let result = engine.execute(entries: entries,
                                    query: PluginListQuery(searchText: "/jb/ellekit/gamma"))
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.displayName, "Gamma Broken.dylib")
    }

    func testE206SearchByBundleID() {
        let entries = makeEntries()
        let result = engine.execute(entries: entries,
                                    query: PluginListQuery(searchText: "com.alpha.app"))
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.bundleIdentifiers, ["com.alpha.app", "com.alpha.tweak"])
    }

    // MARK: - E2-07 ～ E2-09 筛选

    func testE207ConfigurationFilter() {
        let entries = makeEntries()

        let configured = engine.execute(
            entries: entries,
            query: PluginListQuery(filter: PluginListFilter(configuration: .configured)))
        XCTAssertEqual(configured.count, 3) // Alpha / Echo / Delta（valid=true）
        XCTAssertTrue(configured.contains { $0.displayName.hasPrefix("Alpha Tweak") })
        XCTAssertTrue(configured.contains { $0.displayName.hasPrefix("Echo Unmatched") })
        XCTAssertTrue(configured.contains { $0.displayName.hasPrefix("Delta Orphan") })

        let notConfigured = engine.execute(
            entries: entries,
            query: PluginListQuery(filter: PluginListFilter(configuration: .notConfigured)))
        XCTAssertEqual(notConfigured.count, 2) // beta（无 filter）+ zeta（无 filter）

        let unverified = engine.execute(
            entries: entries,
            query: PluginListQuery(filter: PluginListFilter(configuration: .unverified)))
        XCTAssertEqual(unverified.map(\.displayName), ["Gamma Broken.dylib"])
    }

    func testE208AssociationFilter() {
        let entries = makeEntries()

        let associated = engine.execute(
            entries: entries,
            query: PluginListQuery(filter: PluginListFilter(association: .associated)))
        XCTAssertEqual(associated.map(\.displayName), ["Alpha Tweak.dylib"])

        let unassociated = engine.execute(
            entries: entries,
            query: PluginListQuery(filter: PluginListFilter(association: .unassociated)))
        XCTAssertTrue(unassociated.contains { $0.displayName.hasPrefix("beta-plugin") })
        XCTAssertTrue(unassociated.contains { $0.displayName.hasPrefix("Zeta Missing") })

        let global = engine.execute(
            entries: entries,
            query: PluginListQuery(filter: PluginListFilter(association: .globalRule)))
        XCTAssertEqual(global.count, 1)

        let unmatched = engine.execute(
            entries: entries,
            query: PluginListQuery(filter: PluginListFilter(association: .unmatched)))
        XCTAssertEqual(unmatched.map(\.displayName), ["Echo Unmatched.dylib"])

        let invalid = engine.execute(
            entries: entries,
            query: PluginListQuery(filter: PluginListFilter(association: .invalid)))
        XCTAssertEqual(invalid.map(\.displayName), ["Gamma Broken.dylib"])
    }

    func testE209EvidenceFilter() {
        let entries = makeEntries()

        let confirmed = engine.execute(
            entries: entries,
            query: PluginListQuery(filter: PluginListFilter(evidence: .confirmed)))
        XCTAssertEqual(confirmed.count, 4) // alpha / beta / gamma / echo 在位
        XCTAssertTrue(confirmed.allSatisfy { $0.installed == .confirmed })

        let absent = engine.execute(
            entries: entries,
            query: PluginListQuery(filter: PluginListFilter(evidence: .absent)))
        XCTAssertEqual(absent.map(\.displayName), ["Zeta Missing.dylib"])

        let unknown = engine.execute(
            entries: entries,
            query: PluginListQuery(filter: PluginListFilter(evidence: .unknown)))
        XCTAssertEqual(unknown.map(\.displayName), ["Delta Orphan"])
    }

    // MARK: - E2-10 组合 / E2-11～12 排序 / E2-13～14 空态

    func testE210CombinedFiltersApplyTogether() {
        let entries = makeEntries()
        let filter = PluginListFilter(configuration: .configured,
                                      association: .associated,
                                      evidence: .confirmed)
        let result = engine.execute(entries: entries,
                                    query: PluginListQuery(searchText: "alpha", filter: filter))
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.displayName, "Alpha Tweak.dylib")
    }

    func testE211NameAscendingSort() {
        let plugins = ["Banana", "Apple", "Cherry"].map {
            makeDirectPlugin(id: $0.lowercased(), name: $0)
        }
        let entries = PluginListProjection.entries(from: plugins)
        let result = engine.execute(entries: entries, query: PluginListQuery(sort: .nameAscending))
        XCTAssertEqual(result.map(\.displayName), ["Apple", "Banana", "Cherry"])
    }

    func testE212NameDescendingSort() {
        let plugins = ["Banana", "Apple", "Cherry"].map {
            makeDirectPlugin(id: $0.lowercased(), name: $0)
        }
        let entries = PluginListProjection.entries(from: plugins)
        let result = engine.execute(entries: entries, query: PluginListQuery(sort: .nameDescending))
        XCTAssertEqual(result.map(\.displayName), ["Cherry", "Banana", "Apple"])
    }

    func testE213NoSearchResultsReturnsEmpty() {
        let entries = makeEntries()
        let result = engine.execute(entries: entries,
                                    query: PluginListQuery(searchText: "zzz-no-match"))
        XCTAssertTrue(result.isEmpty)
    }

    func testE214EmptySnapshotProducesNoSyntheticEntries() {
        let emptyReport = FKDiagnosticReport(
            generatedAt: Date(), environment: [:],
            roots: [], dynamicLibraryDirectories: [],
            plugins: [], filters: [], injectorEvidence: [], packages: [],
            fileOwnership: [], integrity: [], helperCandidates: [],
            helperRegistrations: [], applications: [], associations: [], findings: [])
        let snapshot = PluginDataMapper.mapSnapshot(report: emptyReport)
        let entries = PluginListProjection.entries(from: snapshot.plugins)
        XCTAssertTrue(entries.isEmpty)
        let result = engine.execute(entries: entries, query: .empty)
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - E2-15 状态语义 / E2-16 不触发扫描

    func testE215LoadedStateRemainsUnknownWithoutRuntimeEvidence() {
        let entries = makeEntries()
        for entry in entries {
            XCTAssertEqual(entry.loaded, .unknown)
        }
    }

    func testE216SearchDoesNotTriggerRepositoryRefresh() {
        let repository = DiagnosticPluginRepository(engine: ReadOnlyDiagnosticsEngine())
        let snapshot = repository.refresh()
        let before = repository.refreshCount

        let entries = PluginListProjection.entries(from: snapshot.plugins)
        _ = engine.execute(entries: entries, query: PluginListQuery(searchText: "a"))
        _ = engine.execute(entries: entries, query: PluginListQuery(filter: .all))
        _ = engine.execute(entries: entries, query: PluginListQuery(sort: .nameDescending))

        XCTAssertEqual(repository.refreshCount, before)
    }

    // MARK: - 直接构造夹具

    private func makeDirectPlugin(id: String, name: String) -> FKPlugin {
        FKPlugin(
            id: id,
            name: name,
            dylibPath: "/jb/\(id).dylib",
            plistPath: nil,
            source: FKPluginSource(raw: "unknown", packageIdentifier: nil,
                                   packageOwners: [], exactPackageRecord: false, evidence: nil),
            status: FKPluginStatus(installed: .confirmed, configured: .absent, loaded: .unknown),
            configuration: nil,
            associations: [],
            fileSize: nil,
            version: nil,
            packageIdentifier: nil,
            raw: [:]
        )
    }
}
