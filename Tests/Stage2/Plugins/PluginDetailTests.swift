//
//  PluginDetailTests.swift
//  FilterKit 0.1-E3 Plugin Detail & App Association Explorer 离线测试
//
//  纯内存夹具：E1 快照 → E3 详情/App 投影 → Resolver 双向查询。不访问文件
//  系统、不触发真实目录枚举；E3-22 验证投影/Resolver 不增加 Repository 扫描次数。
//
//  覆盖规格 §5 矩阵 E3-01 ～ E3-22。
//

import Foundation
import XCTest
@testable import Core

final class PluginDetailTests: XCTestCase {

    private let resolver = PluginAssociationResolver()

    // MARK: - 夹具（经 E1 映射链路构造快照）

    private func makeReport() -> FKDiagnosticReport {
        let plugins: [[String: String]] = [
            [
                "name": "Alpha Tweak.dylib",
                "path": "/jb/ellekit/Alpha Tweak.dylib",
                "exists": "true", "readable": "true", "size": "12345",
                "source": "dpkg_sileo", "loaded": "unknown",
                "package_owners": "com.alpha.tweak", "version": "1.2.0",
                "hash": "abc123"
            ],
            [
                "name": "Beta Multi.dylib",
                "path": "/jb/ellekit/Beta Multi.dylib",
                "exists": "true", "readable": "true", "size": "2000",
                "source": "manual", "loaded": "unknown"
            ],
            [
                "name": "Gamma Shared.dylib",
                "path": "/jb/ellekit/Gamma Shared.dylib",
                "exists": "true", "readable": "true", "size": "3000",
                "source": "manual", "loaded": "unknown"
            ],
            [
                "name": "Delta Global.dylib",
                "path": "/jb/ellekit/Delta Global.dylib",
                "exists": "true", "readable": "true", "size": "4000",
                "source": "unknown", "loaded": "unknown"
            ],
            [
                "name": "Echo Unmatched.dylib",
                "path": "/jb/ellekit/Echo Unmatched.dylib",
                "exists": "true", "readable": "true", "size": "5000",
                "source": "unknown", "loaded": "unknown"
            ],
            [
                "name": "Zeta Invalid.dylib",
                "path": "/jb/ellekit/Zeta Invalid.dylib",
                "exists": "true", "readable": "true", "size": "6000",
                "source": "unknown", "loaded": "unknown"
            ],
            [
                "name": "Eta Unresolved.dylib",
                "path": "/jb/ellekit/Eta Unresolved.dylib",
                "exists": "true", "readable": "true", "size": "7000",
                "source": "unknown", "loaded": "unknown"
            ],
            [
                "name": "Theta Tweak.dylib",
                "path": "/jb/ellekit/Theta Tweak.dylib",
                "exists": "true", "readable": "true", "size": "8000",
                "source": "manual", "loaded": "unknown"
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
                "plugin": "Beta Multi",
                "plist_path": "/jb/ellekit/Beta Multi.plist",
                "read_status": "readable", "parse_status": "parsed",
                "bundles": "com.beta.app", "global": "false", "valid": "true"
            ],
            [
                "plugin": "Gamma Shared",
                "plist_path": "/jb/ellekit/Gamma Shared.plist",
                "read_status": "readable", "parse_status": "parsed",
                "bundles": "com.beta.app", "global": "false", "valid": "true"
            ],
            [
                "plugin": "Delta Global",
                "plist_path": "/jb/ellekit/Delta Global.plist",
                "global": "true", "valid": "true"
            ],
            [
                "plugin": "Echo Unmatched",
                "plist_path": "/jb/ellekit/Echo Unmatched.plist",
                "bundles": "com.echo.nope", "unmatched_bundle_ids": "com.echo.nope",
                "global": "false", "valid": "true"
            ],
            [
                "plugin": "Zeta Invalid",
                "plist_path": "/jb/ellekit/Zeta Invalid.plist",
                "read_status": "read_failed", "parse_status": "read_failed",
                "valid": "false"
            ],
            [
                "plugin": "Eta Unresolved",
                "plist_path": "/jb/ellekit/Eta Unresolved.plist",
                "global": "false", "valid": "true"
            ],
            [
                "plugin": "Theta Tweak",
                "plist_path": "/jb/ellekit/Theta Tweak.plist",
                "bundles": "com.theta.one,com.theta.two", "global": "false", "valid": "true"
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
                "plugin": "Beta Multi", "bundle_id": "com.beta.app",
                "match_type": "bundle", "category": "exact_match",
                "is_global": "false", "matched_app_count": "1",
                "unmatched_target_count": "0", "evidence": "static_filter_match_only",
                "loaded": "unknown"
            ],
            [
                "plugin": "Gamma Shared", "bundle_id": "com.beta.app",
                "match_type": "bundle", "category": "exact_match",
                "is_global": "false", "matched_app_count": "1",
                "unmatched_target_count": "0", "evidence": "static_filter_match_only",
                "loaded": "unknown"
            ],
            [
                "plugin": "Delta Global", "bundle_id": "",
                "match_type": "none", "category": "global",
                "is_global": "true", "matched_app_count": "0",
                "unmatched_target_count": "0", "evidence": "static_filter_match_only",
                "loaded": "unknown"
            ],
            [
                "plugin": "Echo Unmatched", "bundle_id": "com.echo.nope",
                "match_type": "none", "category": "unmatched_target",
                "is_global": "false", "matched_app_count": "0",
                "unmatched_target_count": "1", "evidence": "static_filter_match_only",
                "loaded": "unknown"
            ],
            [
                "plugin": "Zeta Invalid", "bundle_id": "",
                "match_type": "none", "category": "invalid_configuration",
                "is_global": "false", "matched_app_count": "0",
                "unmatched_target_count": "0", "evidence": "static_filter_match_only",
                "loaded": "unknown"
            ],
            [
                "plugin": "Eta Unresolved", "bundle_id": "",
                "match_type": "none", "category": "unresolved_non_bundle_rule",
                "is_global": "false", "matched_app_count": "0",
                "unmatched_target_count": "0", "evidence": "static_filter_match_only",
                "loaded": "unknown"
            ],
            [
                "plugin": "Theta Tweak", "bundle_id": "com.theta.one",
                "match_type": "bundle", "category": "exact_match",
                "is_global": "false", "matched_app_count": "1",
                "unmatched_target_count": "0", "evidence": "static_filter_match_only",
                "loaded": "unknown"
            ],
            [
                "plugin": "Theta Tweak", "bundle_id": "com.theta.two",
                "match_type": "bundle", "category": "exact_match",
                "is_global": "false", "matched_app_count": "1",
                "unmatched_target_count": "0", "evidence": "static_filter_match_only",
                "loaded": "unknown"
            ]
        ]

        let applications: [[String: String]] = [
            ["bundle_id": "com.alpha.app", "name": "App Alpha", "version": "1.0", "executable": "Alpha", "is_system": "false"],
            ["bundle_id": "com.beta.app", "name": "App Beta", "version": "", "executable": "Beta", "is_system": "false"],
            ["bundle_id": "com.echo.nope", "name": "Echo Nope", "version": "", "executable": "Echo", "is_system": "false"],
            ["bundle_id": "com.theta.one", "name": "Theta One", "version": "", "executable": "Theta", "is_system": "false"],
            ["bundle_id": "com.theta.two", "name": "Theta Two", "version": "", "executable": "Theta", "is_system": "false"]
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

    private func snapshot() -> PluginSnapshot {
        PluginDataMapper.mapSnapshot(report: makeReport())
    }

    private func plugin(prefix: String, in snapshot: PluginSnapshot) -> FKPlugin? {
        snapshot.plugins.first { $0.name.lowercased().hasPrefix(prefix.lowercased()) }
    }

    // MARK: - E3-01 ～ E3-04 映射与文件/归属

    func testE301PluginDetailMapping() {
        let snapshot = snapshot()
        guard let plugin = plugin(prefix: "Alpha Tweak", in: snapshot),
              let detail = PluginDetailProjection.detail(forPluginID: plugin.id, snapshot: snapshot) else {
            return XCTFail("缺少 Alpha 插件详情")
        }

        XCTAssertEqual(detail.displayName, "Alpha Tweak.dylib")
        XCTAssertEqual(detail.fileName, "Alpha Tweak.dylib")
        XCTAssertEqual(detail.filePath, "/jb/ellekit/Alpha Tweak.dylib")
        XCTAssertEqual(detail.version, "1.2.0")
        XCTAssertEqual(detail.packageIdentifier, "com.alpha.tweak")
        XCTAssertEqual(detail.installed, .confirmed)
        XCTAssertEqual(detail.configured, .confirmed)
        XCTAssertEqual(detail.loaded, .unknown)
        XCTAssertEqual(detail.associations.count, 1)
        XCTAssertEqual(detail.exactMatchCount, 1)
    }

    func testE302ApplicationDetailMapping() {
        let snapshot = snapshot()
        guard let detail = ApplicationDetailProjection.detail(forAppID: "com.alpha.app", snapshot: snapshot) else {
            return XCTFail("缺少 App Alpha 详情")
        }

        XCTAssertEqual(detail.displayName, "App Alpha")
        XCTAssertEqual(detail.bundleIdentifier, "com.alpha.app")
        XCTAssertEqual(detail.executable, "Alpha")
        XCTAssertEqual(detail.version, "1.0")
        XCTAssertEqual(detail.associations.count, 1)
        XCTAssertEqual(detail.exactMatchCount, 1)
    }

    func testE303FileInformationPassthrough() {
        let snapshot = snapshot()
        guard let alpha = plugin(prefix: "Alpha Tweak", in: snapshot),
              let alphaDetail = PluginDetailProjection.detail(forPluginID: alpha.id, snapshot: snapshot),
              let beta = plugin(prefix: "Beta Multi", in: snapshot),
              let betaDetail = PluginDetailProjection.detail(forPluginID: beta.id, snapshot: snapshot) else {
            return XCTFail("缺少夹具插件")
        }

        XCTAssertEqual(alphaDetail.filePath, "/jb/ellekit/Alpha Tweak.dylib")
        XCTAssertEqual(alphaDetail.fileSize, 12345)
        XCTAssertEqual(alphaDetail.fileHash, "abc123")
        XCTAssertNil(betaDetail.fileHash)
    }

    func testE304PackageOwnershipNotFabricated() {
        let snapshot = snapshot()
        guard let alpha = plugin(prefix: "Alpha Tweak", in: snapshot),
              let alphaDetail = PluginDetailProjection.detail(forPluginID: alpha.id, snapshot: snapshot),
              let echo = plugin(prefix: "Echo Unmatched", in: snapshot),
              let echoDetail = PluginDetailProjection.detail(forPluginID: echo.id, snapshot: snapshot) else {
            return XCTFail("缺少夹具插件")
        }

        XCTAssertEqual(alphaDetail.packageIdentifier, "com.alpha.tweak")
        XCTAssertEqual(alphaDetail.packageOwners, ["com.alpha.tweak"])
        XCTAssertNil(echoDetail.packageIdentifier)
        XCTAssertTrue(echoDetail.packageOwners.isEmpty)
    }

    // MARK: - E3-05 ～ E3-07 三态透传

    func testE305InstalledStatePassthrough() {
        let snapshot = snapshot()
        guard let alpha = plugin(prefix: "Alpha Tweak", in: snapshot),
              let missing = plugin(prefix: "Zeta Missing", in: snapshot) else {
            return XCTFail("缺少夹具插件")
        }
        XCTAssertEqual(PluginDetailProjection.entry(from: alpha).installed, .confirmed)
        XCTAssertEqual(PluginDetailProjection.entry(from: missing).installed, .absent)
    }

    func testE306ConfiguredStatePassthrough() {
        let snapshot = snapshot()
        guard let invalid = plugin(prefix: "Zeta Invalid", in: snapshot),
              let missing = plugin(prefix: "Zeta Missing", in: snapshot) else {
            return XCTFail("缺少夹具插件")
        }
        XCTAssertEqual(PluginDetailProjection.entry(from: invalid).configured, .unverified)
        XCTAssertEqual(PluginDetailProjection.entry(from: missing).configured, .absent)
    }

    func testE307LoadedRemainsUnknownWithoutRuntimeEvidence() {
        let snapshot = snapshot()
        for plugin in snapshot.plugins {
            XCTAssertEqual(PluginDetailProjection.entry(from: plugin).loaded, .unknown)
        }
    }

    // MARK: - E3-08 ～ E3-12 关联分类语义

    func testE308ExactMatchCountOnlyExact() {
        let snapshot = snapshot()
        guard let alpha = plugin(prefix: "Alpha Tweak", in: snapshot),
              let beta = plugin(prefix: "Beta Multi", in: snapshot) else {
            return XCTFail("缺少夹具插件")
        }
        XCTAssertEqual(PluginDetailProjection.entry(from: alpha).exactMatchCount, 1)
        XCTAssertEqual(PluginDetailProjection.entry(from: beta).exactMatchCount, 1)
    }

    func testE309GlobalRuleNotCountedAsExact() {
        let snapshot = snapshot()
        guard let delta = plugin(prefix: "Delta Global", in: snapshot),
              let detail = PluginDetailProjection.detail(forPluginID: delta.id, snapshot: snapshot) else {
            return XCTFail("缺少 Delta 插件")
        }
        XCTAssertEqual(detail.exactMatchCount, 0)
        XCTAssertEqual(detail.count(of: .globalRule), 1)
    }

    func testE310UnmatchedTargetPreservedAsNotAssociated() {
        let snapshot = snapshot()
        guard let echo = plugin(prefix: "Echo Unmatched", in: snapshot),
              let detail = PluginDetailProjection.detail(forPluginID: echo.id, snapshot: snapshot) else {
            return XCTFail("缺少 Echo 插件")
        }
        XCTAssertEqual(detail.associations.first?.category, .unmatchedTarget)
        XCTAssertEqual(detail.exactMatchCount, 0)
    }

    func testE311InvalidConfigurationPreserved() {
        let snapshot = snapshot()
        guard let invalid = plugin(prefix: "Zeta Invalid", in: snapshot),
              let detail = PluginDetailProjection.detail(forPluginID: invalid.id, snapshot: snapshot) else {
            return XCTFail("缺少 Invalid 插件")
        }
        XCTAssertEqual(detail.associations.first?.category, .invalidConfiguration)
    }

    func testE312UnresolvedPreserved() {
        let snapshot = snapshot()
        guard let eta = plugin(prefix: "Eta Unresolved", in: snapshot),
              let detail = PluginDetailProjection.detail(forPluginID: eta.id, snapshot: snapshot) else {
            return XCTFail("缺少 Eta 插件")
        }
        XCTAssertEqual(detail.associations.first?.category, .unresolved)
    }

    // MARK: - E3-13 ～ E3-14 双向 Resolver

    func testE313ResolverPluginToApp() {
        let snapshot = snapshot()
        let entries = ApplicationDetailProjection.allAssociationEntries(from: snapshot)
        guard let alpha = plugin(prefix: "Alpha Tweak", in: snapshot) else {
            return XCTFail("缺少 Alpha 插件")
        }

        let linked = resolver.associations(forPluginID: alpha.id, from: entries)
        XCTAssertEqual(linked.compactMap(\.applicationID), ["com.alpha.app"])
        XCTAssertEqual(resolver.exactMatches(forPluginID: alpha.id, from: entries).count, 1)
    }

    func testE314ResolverAppToPlugin() {
        let snapshot = snapshot()
        let entries = ApplicationDetailProjection.allAssociationEntries(from: snapshot)

        let linked = resolver.associations(forApplicationID: "com.beta.app", from: entries)
        XCTAssertEqual(linked.count, 2)
        XCTAssertEqual(resolver.exactMatches(forApplicationID: "com.beta.app", from: entries).count, 2)
    }

    // MARK: - E3-15 ～ E3-17 空态与缺失 ID

    func testE315NoAssociationRecordsProduceEmpty() {
        let snapshot = snapshot()
        guard let missing = plugin(prefix: "Zeta Missing", in: snapshot),
              let detail = PluginDetailProjection.detail(forPluginID: missing.id, snapshot: snapshot) else {
            return XCTFail("缺少 Missing 插件")
        }
        XCTAssertTrue(detail.associations.isEmpty)
        XCTAssertEqual(detail.exactMatchCount, 0)
    }

    func testE316UnknownPluginIDProducesNoFabricatedDetail() {
        let snapshot = snapshot()
        XCTAssertNil(PluginDetailProjection.detail(forPluginID: "no-such-plugin", snapshot: snapshot))
    }

    func testE317UnknownAppIDProducesNoFabricatedDetail() {
        let snapshot = snapshot()
        XCTAssertNil(ApplicationDetailProjection.detail(forAppID: "no.such.app", snapshot: snapshot))
    }

    // MARK: - E3-18 ～ E3-20 去重与多对多

    func testE318DuplicateAssociationNotRepeated() {
        let duplicate = PluginAssociationEntry(
            id: "dup|com.app|bundle", pluginID: "p1", applicationID: "com.app",
            category: .exactMatch, matchType: "bundle", isGlobal: false,
            matchedAppCount: 1, unmatchedTargetCount: 0,
            evidenceDescription: nil, loaded: "unknown"
        )
        let entries = [duplicate, duplicate]

        let linked = resolver.associations(forPluginID: "p1", from: entries)
        XCTAssertEqual(linked.count, 1)
        XCTAssertEqual(linked.first?.id, duplicate.id)
    }

    func testE319MultiplePluginsOneAppComplete() {
        let snapshot = snapshot()
        guard let detail = ApplicationDetailProjection.detail(forAppID: "com.beta.app", snapshot: snapshot) else {
            return XCTFail("缺少 App Beta")
        }
        XCTAssertEqual(detail.associations.count, 2)
        XCTAssertEqual(detail.exactMatchCount, 2)
        let pluginIDs = Set(detail.associations.map(\.pluginID))
        XCTAssertEqual(pluginIDs.count, 2)
    }

    func testE320MultipleAppsOnePluginComplete() {
        let snapshot = snapshot()
        guard let theta = plugin(prefix: "Theta Tweak", in: snapshot),
              let detail = PluginDetailProjection.detail(forPluginID: theta.id, snapshot: snapshot) else {
            return XCTFail("缺少 Theta 插件")
        }
        XCTAssertEqual(detail.associations.count, 2)
        XCTAssertEqual(detail.exactMatchCount, 2)
        let appIDs = Set(detail.associations.compactMap(\.applicationID))
        XCTAssertEqual(appIDs, ["com.theta.one", "com.theta.two"])
    }

    // MARK: - E3-21 快照一致性 / E3-22 只读隔离

    func testE321BothDirectionsShareSameSnapshotProjection() {
        let snapshot = snapshot()
        let entries = ApplicationDetailProjection.allAssociationEntries(from: snapshot)

        guard let alpha = plugin(prefix: "Alpha Tweak", in: snapshot),
              let pluginDetail = PluginDetailProjection.detail(forPluginID: alpha.id, snapshot: snapshot),
              let appDetail = ApplicationDetailProjection.detail(forAppID: "com.alpha.app", snapshot: snapshot) else {
            return XCTFail("缺少双向夹具")
        }

        let pluginLinked = resolver.associations(forPluginID: alpha.id, from: entries)
        let appLinked = resolver.associations(forApplicationID: "com.alpha.app", from: entries)
        XCTAssertEqual(pluginLinked.map(\.id), appLinked.map(\.id))
        XCTAssertEqual(pluginDetail.associations.map(\.id), appDetail.associations.map(\.id))
    }

    func testE322ProjectionIsPureAndDoesNotTriggerRepositoryScan() {
        // 扫描次数断言走真实 Repository：Runner 无越狱环境时快照可为空，不假设
        // 扫描到插件；投影/Resolver 调用不得触发二次 refresh。
        let repository = DiagnosticPluginRepository(engine: ReadOnlyDiagnosticsEngine())
        let repoSnapshot = repository.refresh()
        let before = repository.refreshCount

        let entries = ApplicationDetailProjection.allAssociationEntries(from: repoSnapshot)
        for plugin in repoSnapshot.plugins {
            _ = PluginDetailProjection.entry(from: plugin)
        }
        for app in repoSnapshot.applications {
            _ = ApplicationDetailProjection.entry(from: app, associations: repoSnapshot.associations)
        }
        _ = resolver.associations(forPluginID: repoSnapshot.plugins.first?.id ?? "", from: entries)
        _ = resolver.associations(forApplicationID: repoSnapshot.applications.first?.bundleID ?? "", from: entries)

        XCTAssertEqual(repository.refreshCount, before)

        // 纯函数一致性：同一输入两次投影结果一致；使用离线合成快照，不依赖 Runner
        // 真机/越狱环境是否扫描到插件。注意局部快照不得命名为 `snapshot`，以免遮蔽
        // 本类合成快照助手方法 `snapshot()`。
        let synthetic = self.snapshot()
        guard let plugin = synthetic.plugins.first else { return XCTFail("合成快照缺插件") }
        XCTAssertEqual(PluginDetailProjection.entry(from: plugin), PluginDetailProjection.entry(from: plugin))
    }
}
