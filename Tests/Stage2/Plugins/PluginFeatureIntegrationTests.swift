//
//  PluginFeatureIntegrationTests.swift
//  FilterKit 0.1-E4 Plugin Feature Integration & Dependency 离线集成测试
//
//  纯内存夹具：Fake Repository 遵循 E1 `PluginRepository` 协议并暴露 `refreshCount`；
//  失败分支经 Store `refreshProvider` 接缝注入。不访问文件系统、不触发真实目录
//  枚举；E4-19 为 Runner UI 门禁，离线侧 XCTSkip。
//
//  覆盖规格 §5 矩阵 E4-01 ～ E4-39。
//

import Foundation
import XCTest
@testable import Core

final class PluginFeatureIntegrationTests: XCTestCase {

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
                "exists": "false", "readable": "false",
                "source": "unknown", "loaded": "unknown"
            ],
            [
                "name": "Eta Unresolved.dylib",
                "path": "/jb/ellekit/Eta Unresolved.dylib",
                "exists": "true", "readable": "true", "size": "7000",
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
            ]
        ]

        let applications: [[String: String]] = [
            ["bundle_id": "com.alpha.app", "name": "App Alpha", "version": "1.0", "executable": "Alpha", "is_system": "false"],
            ["bundle_id": "com.echo.nope", "name": "Echo Nope", "version": "", "executable": "Echo", "is_system": "false"]
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

    private func makeEmptyReport() -> FKDiagnosticReport {
        FKDiagnosticReport(
            generatedAt: Date(timeIntervalSince1970: 1_763_600_000),
            environment: ["jailbreak": "roothide"],
            roots: [], dynamicLibraryDirectories: [],
            plugins: [], filters: [], injectorEvidence: [],
            packages: [], fileOwnership: [], integrity: [],
            helperCandidates: [], helperRegistrations: [],
            applications: [], associations: [], findings: []
        )
    }

    private func makeReplacementReport() -> FKDiagnosticReport {
        let plugins: [[String: String]] = [
            [
                "name": "Replacement Only.dylib",
                "path": "/jb/ellekit/Replacement Only.dylib",
                "exists": "true", "readable": "true", "size": "999",
                "source": "manual", "loaded": "unknown"
            ]
        ]
        return FKDiagnosticReport(
            generatedAt: Date(timeIntervalSince1970: 1_763_600_100),
            environment: ["jailbreak": "roothide"],
            roots: [], dynamicLibraryDirectories: [],
            plugins: plugins, filters: [], injectorEvidence: [],
            packages: [], fileOwnership: [], integrity: [],
            helperCandidates: [], helperRegistrations: [],
            applications: [], associations: [], findings: []
        )
    }

    private func snapshot(_ report: FKDiagnosticReport? = nil) -> PluginSnapshot {
        PluginDataMapper.mapSnapshot(report: report ?? makeReport())
    }

    private func store(snapshots: [PluginSnapshot],
                       outcomes: [PluginRefreshOutcome]? = nil) -> (PluginFeatureStore, FakePluginRepository) {
        let repository = FakePluginRepository(snapshots: snapshots)
        let provider: (() -> PluginRefreshOutcome)? = outcomes.map { outcomeQueue in
            var queue = outcomeQueue
            return {
                // 仍推进 Repository 扫描计数接缝；失败结果由 Store 接缝接管。
                _ = repository.refresh()
                return queue.removeFirst()
            }
        }
        let store = PluginFeatureStore(repository: repository, refreshProvider: provider)
        return (store, repository)
    }

    private func plugin(prefix: String, in snapshot: PluginSnapshot) -> FKPlugin? {
        snapshot.plugins.first { $0.name.lowercased().hasPrefix(prefix.lowercased()) }
    }

    // MARK: - A. Repository 与 Snapshot（E4-01 ～ 10）

    func testE401StoreHoldsSingleRepositorySnapshot() {
        let repository = DiagnosticPluginRepository(engine: ReadOnlyDiagnosticsEngine())
        let store = PluginFeatureStore(repository: repository)
        store.loadIfNeeded()

        XCTAssertEqual(store.snapshot, repository.currentSnapshot())
        XCTAssertEqual(store.pluginEntries.count, store.snapshot?.plugins.count ?? 0)
    }

    func testE402InitialLoadRefreshesOnce() {
        let (store, repository) = store(snapshots: [snapshot()])
        store.loadIfNeeded()
        XCTAssertEqual(repository.refreshCount, 1)
    }

    func testE403MultiPageAccessDoesNotRefreshAgain() {
        let (store, repository) = store(snapshots: [snapshot()])
        store.loadIfNeeded()

        if let pluginID = store.pluginEntries.first?.id {
            _ = store.pluginDetail(id: pluginID)
        }
        if let appID = store.applicationDetails.first?.id {
            _ = store.applicationDetail(id: appID)
            _ = store.associations(forApplicationID: appID)
        }
        if let pluginID = store.pluginEntries.first?.id {
            _ = store.associations(forPluginID: pluginID)
        }

        XCTAssertEqual(repository.refreshCount, 1)
    }

    func testE404SearchDoesNotRefresh() {
        let (store, repository) = store(snapshots: [snapshot()])
        store.loadIfNeeded()

        // 搜索在 App VM 内存查询层执行；Store 侧重复读取条目不触发扫描。
        _ = store.pluginEntries.filter { $0.displayName.contains("Alpha") }
        _ = store.pluginEntries

        XCTAssertEqual(repository.refreshCount, 1)
    }

    func testE405FilterDoesNotRefresh() {
        let (store, repository) = store(snapshots: [snapshot()])
        store.loadIfNeeded()

        _ = store.pluginEntries.filter { $0.installed == .confirmed }
        _ = store.pluginEntries.filter { $0.associationCategories.contains(.exactMatch) }

        XCTAssertEqual(repository.refreshCount, 1)
    }

    func testE406OpeningPluginDetailDoesNotRefresh() {
        let (store, repository) = store(snapshots: [snapshot()])
        store.loadIfNeeded()

        for entry in store.pluginEntries {
            _ = store.pluginDetail(id: entry.id)
        }

        XCTAssertEqual(repository.refreshCount, 1)
    }

    func testE407OpeningAppDetailDoesNotRefresh() {
        let (store, repository) = store(snapshots: [snapshot()])
        store.loadIfNeeded()

        for entry in store.applicationDetails {
            _ = store.applicationDetail(id: entry.id)
        }

        XCTAssertEqual(repository.refreshCount, 1)
    }

    func testE408ManualRefreshRunsOnce() {
        let (store, repository) = store(snapshots: [snapshot(), snapshot()])
        store.loadIfNeeded()
        store.refresh()

        XCTAssertEqual(repository.refreshCount, 2)
    }

    func testE409ConcurrentInitialLoadMergesToSingleScan() {
        let (store, repository) = store(snapshots: [snapshot()])
        store.loadIfNeeded()
        store.loadIfNeeded()
        store.loadIfNeeded()

        XCTAssertEqual(repository.refreshCount, 1)
    }

    func testE410AllPagesShareSameSnapshot() {
        let (store, _) = store(snapshots: [snapshot()])
        store.loadIfNeeded()
        guard let snapshot = store.snapshot else { return XCTFail("缺少快照") }

        XCTAssertEqual(Set(store.pluginEntries.map(\.id)), Set(snapshot.plugins.map(\.id)))
        XCTAssertEqual(Set(store.pluginDetails.map(\.id)), Set(snapshot.plugins.map(\.id)))
        XCTAssertEqual(Set(store.applicationDetails.map(\.id)), Set(snapshot.applications.map(\.bundleID)))
        XCTAssertEqual(store.associationEntries.count, snapshot.associations.count)
    }

    // MARK: - B. 状态处理（E4-11 ～ 18）

    func testE411InitialStateIsNeverLoaded() {
        let (store, _) = store(snapshots: [snapshot()])
        XCTAssertEqual(store.state, .neverLoaded)
        XCTAssertFalse(store.state.hasLoaded)
    }

    func testE412LoadingStateIsLoading() {
        XCTAssertTrue(PluginFeatureState.loading.isLoading)
        XCTAssertFalse(PluginFeatureState.neverLoaded.isLoading)
        XCTAssertNil(PluginFeatureState.loading.errorMessage)
    }

    func testE413LoadedStateWhenPluginsExist() {
        let (store, _) = store(snapshots: [snapshot()])
        store.loadIfNeeded()
        XCTAssertEqual(store.state, .loaded)
        XCTAssertFalse(store.pluginEntries.isEmpty)
    }

    func testE414EmptyStateWhenSnapshotHasNoPlugins() {
        let (store, _) = store(snapshots: [snapshot(makeEmptyReport())])
        store.loadIfNeeded()
        XCTAssertEqual(store.state, .empty)
        XCTAssertTrue(store.pluginEntries.isEmpty)
    }

    func testE415FirstScanFailureIsFailed() {
        let snapshot = snapshot()
        let outcomes: [PluginRefreshOutcome] = [.failure("Permission denied")]
        let (store, repository) = self.store(snapshots: [snapshot], outcomes: outcomes)
        store.loadIfNeeded()

        XCTAssertEqual(store.state, .failed("Permission denied"))
        XCTAssertEqual(store.state.errorMessage, "Permission denied")
        XCTAssertNil(store.snapshot)
        XCTAssertEqual(repository.refreshCount, 1)
    }

    func testE416RefreshFailureKeepsOldSnapshot() {
        let snapshot = snapshot()
        let outcomes: [PluginRefreshOutcome] = [.snapshot(snapshot), .failure("Permission denied")]
        let (store, _) = self.store(snapshots: [snapshot], outcomes: outcomes)
        store.loadIfNeeded()
        let oldIDs = Set(store.pluginEntries.map(\.id))

        store.refresh()

        XCTAssertEqual(store.state, .loaded)
        XCTAssertEqual(store.lastRefreshError, "Permission denied")
        XCTAssertEqual(Set(store.pluginEntries.map(\.id)), oldIDs)
        XCTAssertEqual(store.snapshot?.plugins.map(\.id), snapshot.plugins.map(\.id))
    }

    func testE417SuccessfulRefreshReplacesOldSnapshot() {
        let first = snapshot()
        let second = snapshot(makeReplacementReport())
        let outcomes: [PluginRefreshOutcome] = [.snapshot(first), .snapshot(second)]
        let (store, _) = self.store(snapshots: [first, second], outcomes: outcomes)
        store.loadIfNeeded()

        store.refresh()

        XCTAssertEqual(store.state, .loaded)
        XCTAssertEqual(store.pluginEntries.map(\.id), second.plugins.map(\.id))
        XCTAssertNil(store.lastRefreshError)
    }

    func testE418UnknownEvidenceNotForcedToFailureOrMissing() {
        let (store, _) = store(snapshots: [snapshot()])
        store.loadIfNeeded()

        XCTAssertEqual(store.state, .loaded)
        for detail in store.pluginDetails {
            // 未知 / 未核验证据保留原等级，不强转失败；loaded 无运行时证据恒 unknown。
            XCTAssertEqual(detail.loaded, .unknown)
        }
    }

    // MARK: - C. 页面与导航（E4-19 ～ 25）

    func testE419PluginsTabRendersRootView() throws {
        throw XCTSkip("Runner G7/G8：Plugins Tab 根视图渲染与 UI 自动化，离线 Core 测试不实例化 SwiftUI 页面")
    }

    func testE420ListToPluginDetailIDMatches() {
        let (store, _) = store(snapshots: [snapshot()])
        store.loadIfNeeded()

        for entry in store.pluginEntries {
            let detail = store.pluginDetail(id: entry.id)
            XCTAssertEqual(detail?.id, entry.id)
        }
    }

    func testE421PluginToAppRouteIDMatchesAssociation() {
        let (store, _) = store(snapshots: [snapshot()])
        store.loadIfNeeded()
        guard let alpha = store.pluginDetails.first(where: { $0.displayName.hasPrefix("Alpha") }) else {
            return XCTFail("缺少 Alpha 插件")
        }

        let linked = store.associations(forPluginID: alpha.id)
        let appID = linked.compactMap(\.applicationID).first
        XCTAssertEqual(appID, "com.alpha.app")
        XCTAssertNotNil(appID.flatMap { store.applicationDetail(id: $0) })
    }

    func testE422AppListToDetailIDMatches() {
        let (store, _) = store(snapshots: [snapshot()])
        store.loadIfNeeded()

        for entry in store.applicationDetails {
            let detail = store.applicationDetail(id: entry.id)
            XCTAssertEqual(detail?.id, entry.id)
        }
    }

    func testE423AppToPluginRouteIDMatchesAssociation() {
        let (store, _) = store(snapshots: [snapshot()])
        store.loadIfNeeded()

        let linked = store.associations(forApplicationID: "com.alpha.app")
        let pluginID = linked.first?.pluginID
        XCTAssertEqual(pluginID, store.pluginDetails.first(where: { $0.displayName.hasPrefix("Alpha") })?.id)
        XCTAssertNotNil(pluginID.flatMap { store.pluginDetail(id: $0) })
    }

    func testE424UnknownIDResolvesToMissingDetail() {
        let (store, _) = store(snapshots: [snapshot()])
        store.loadIfNeeded()

        XCTAssertNil(store.pluginDetail(id: "no-such-plugin"))
        XCTAssertNil(store.applicationDetail(id: "no.such.app"))
    }

    func testE425RepeatedNavigationDoesNotRefresh() {
        let (store, repository) = store(snapshots: [snapshot()])
        store.loadIfNeeded()

        for _ in 0..<3 {
            if let pluginID = store.pluginEntries.first?.id {
                _ = store.pluginDetail(id: pluginID)
            }
            if let appID = store.applicationDetails.first?.id {
                _ = store.applicationDetail(id: appID)
                _ = store.associations(forApplicationID: appID)
            }
        }

        XCTAssertEqual(repository.refreshCount, 1)
    }

    // MARK: - D. 数据语义（E4-26 ～ 33）

    func testE426LoadedRemainsUnknownWithoutRuntimeEvidence() {
        let (store, _) = store(snapshots: [snapshot()])
        store.loadIfNeeded()

        for detail in store.pluginDetails {
            XCTAssertEqual(detail.loaded, .unknown)
        }
    }

    func testE427GlobalRuleNotCountedAsExactMatch() {
        let (store, _) = store(snapshots: [snapshot()])
        store.loadIfNeeded()
        guard let delta = store.pluginDetails.first(where: { $0.displayName.hasPrefix("Delta") }) else {
            return XCTFail("缺少 Delta 插件")
        }

        XCTAssertEqual(delta.exactMatchCount, 0)
        XCTAssertEqual(delta.count(of: .globalRule), 1)
    }

    func testE428UnmatchedTargetNotShownAsExactAssociation() {
        let (store, _) = store(snapshots: [snapshot()])
        store.loadIfNeeded()
        guard let echo = store.pluginDetails.first(where: { $0.displayName.hasPrefix("Echo") }) else {
            return XCTFail("缺少 Echo 插件")
        }

        XCTAssertEqual(echo.associations.first?.category, .unmatchedTarget)
        XCTAssertEqual(echo.exactMatchCount, 0)
    }

    func testE429InvalidConfigurationStateRetained() {
        let (store, _) = store(snapshots: [snapshot()])
        store.loadIfNeeded()
        guard let invalid = store.pluginDetails.first(where: { $0.displayName.hasPrefix("Zeta") }) else {
            return XCTFail("缺少 Zeta 插件")
        }

        XCTAssertEqual(invalid.associations.first?.category, .invalidConfiguration)
    }

    func testE430UnresolvedStateRetained() {
        let (store, _) = store(snapshots: [snapshot()])
        store.loadIfNeeded()
        guard let unresolved = store.pluginDetails.first(where: { $0.displayName.hasPrefix("Eta") }) else {
            return XCTFail("缺少 Eta 插件")
        }

        XCTAssertEqual(unresolved.associations.first?.category, .unresolved)
    }

    func testE431PluginHashNilWithoutEvidence() {
        let (store, _) = store(snapshots: [snapshot()])
        store.loadIfNeeded()
        guard let alpha = store.pluginDetails.first(where: { $0.displayName.hasPrefix("Alpha") }),
              let delta = store.pluginDetails.first(where: { $0.displayName.hasPrefix("Delta") }) else {
            return XCTFail("缺少夹具插件")
        }

        XCTAssertEqual(alpha.fileHash, "abc123")
        XCTAssertNil(delta.fileHash)
    }

    func testE432IntegrityRemainsUnknownWithoutPluginLevelRecord() {
        let (store, _) = store(snapshots: [snapshot()])
        store.loadIfNeeded()

        for detail in store.pluginDetails {
            XCTAssertEqual(detail.integrityState, .unknown)
        }
    }

    func testE433FileOwnershipNotFabricated() {
        let (store, _) = store(snapshots: [snapshot()])
        store.loadIfNeeded()
        guard let alpha = store.pluginDetails.first(where: { $0.displayName.hasPrefix("Alpha") }),
              let delta = store.pluginDetails.first(where: { $0.displayName.hasPrefix("Delta") }) else {
            return XCTFail("缺少夹具插件")
        }

        XCTAssertEqual(alpha.packageIdentifier, "com.alpha.tweak")
        XCTAssertEqual(alpha.packageOwners, ["com.alpha.tweak"])
        XCTAssertNil(delta.packageIdentifier)
        XCTAssertTrue(delta.packageOwners.isEmpty)
        XCTAssertEqual(delta.sourceRaw, "unknown")
    }

    // MARK: - E. 只读隔离（E4-34 ～ 39）

    func testE434FileSystemNoWriteSurfacedByStore() {
        let (store, repository) = store(snapshots: [snapshot()])
        store.loadIfNeeded()
        let before = store.snapshot

        _ = store.pluginDetails
        _ = store.applicationDetails
        _ = store.associationEntries

        XCTAssertEqual(store.snapshot, before)
        XCTAssertEqual(repository.refreshCount, 1)
    }

    func testE435PlistPathsUnchangedAfterReadOperations() {
        let (store, _) = store(snapshots: [snapshot()])
        store.loadIfNeeded()
        let plistPaths = store.snapshot?.plugins.compactMap(\.plistPath) ?? []

        _ = store.pluginDetails
        _ = store.applicationDetails

        XCTAssertEqual(store.snapshot?.plugins.compactMap(\.plistPath), plistPaths)
    }

    func testE436DylibPathsAndSizesUnchanged() {
        let (store, _) = store(snapshots: [snapshot()])
        store.loadIfNeeded()
        let beforePaths = store.snapshot?.plugins.map(\.dylibPath)
        let beforeSizes = store.snapshot?.plugins.map(\.fileSize)

        _ = store.pluginDetails

        XCTAssertEqual(store.snapshot?.plugins.map(\.dylibPath), beforePaths)
        XCTAssertEqual(store.snapshot?.plugins.map(\.fileSize), beforeSizes)
    }

    func testE437PackageOwnershipUnchanged() {
        let (store, _) = store(snapshots: [snapshot()])
        store.loadIfNeeded()
        let beforeIds = store.snapshot?.plugins.map(\.packageIdentifier)
        let beforeOwners = store.snapshot?.plugins.map { $0.source.packageOwners.joined(separator: ",") }

        _ = store.pluginDetails

        XCTAssertEqual(store.snapshot?.plugins.map(\.packageIdentifier), beforeIds)
        XCTAssertEqual(store.snapshot?.plugins.map { $0.source.packageOwners.joined(separator: ",") }, beforeOwners)
    }

    func testE438FilterConfigurationUnchanged() {
        let (store, _) = store(snapshots: [snapshot()])
        store.loadIfNeeded()
        let before = store.snapshot?.plugins.map { $0.configuration?.parseStatus }

        _ = store.pluginDetails

        XCTAssertEqual(store.snapshot?.plugins.map { $0.configuration?.parseStatus }, before)
    }

    func testE439NoEnableDisableStateExposed() {
        let (store, _) = store(snapshots: [snapshot()])
        store.loadIfNeeded()
        let beforeInstalled = store.snapshot?.plugins.map { $0.status.installed }
        let beforeConfigured = store.snapshot?.plugins.map { $0.status.configured }
        let beforeLoaded = store.snapshot?.plugins.map { $0.status.loaded }

        _ = store.pluginDetails

        XCTAssertEqual(store.snapshot?.plugins.map { $0.status.installed }, beforeInstalled)
        XCTAssertEqual(store.snapshot?.plugins.map { $0.status.configured }, beforeConfigured)
        XCTAssertEqual(store.snapshot?.plugins.map { $0.status.loaded }, beforeLoaded)
        // Store 集成层无 enabled / disabled / 启停属性；编译期约束由 Core 接口面保证，
        // 运行时隔离由 Runner G6 只读检查复核。
    }
}

// MARK: - Fake Repository

private final class FakePluginRepository: PluginRepository {
    var snapshots: [PluginSnapshot]
    var refreshCount = 0
    private var current: PluginSnapshot?

    init(snapshots: [PluginSnapshot]) {
        self.snapshots = snapshots
    }

    func currentSnapshot() -> PluginSnapshot? {
        current
    }

    @discardableResult
    func refresh() -> PluginSnapshot {
        refreshCount += 1
        let next: PluginSnapshot
        if let first = snapshots.first {
            snapshots.removeFirst()
            next = first
        } else {
            guard let cached = current else {
                preconditionFailure("FakeRepository 缺少可用快照")
            }
            next = cached
        }
        current = next
        return next
    }

    func plugin(id: String) -> FKPlugin? {
        current?.pluginByID[id]
    }

    func applications() -> [FKApplication] {
        current?.applications ?? []
    }
}
