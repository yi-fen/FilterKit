//
//  PluginFeatureStore.swift
//  FilterKit 0.1-E4 Plugin Feature Integration & Dependency
//
//  插件功能唯一数据持有者：一个 Repository、一份 PluginSnapshot、三类投影与
//  双向关联条目在此统一重建，E2 列表 / E3 插件详情 / App 详情 / App 列表消费
//  同一份数据。Store 不触发文件写入、不暴露启停 / 删除 / 改 Filter 接口。
//
//  签名偏差（E4 规格 §3.2）：E1 Repository 为同步、非 throwing 协议；备忘录
//  示例的 `try await refresh()` 不适用。失败分支经 `refreshProvider` 接缝落地，
//  供离线测试覆盖 failed / 旧数据保留语义；真机错误信号待引擎开放错误通道回填。
//

import Foundation
import Observation

/// 一次刷新的结果；默认路径由 Repository 同步快照包装为 `.snapshot`。
public enum PluginRefreshOutcome: Equatable, Sendable {
    case snapshot(PluginSnapshot)
    case failure(String)
}

/// 插件功能共享 Store（App 组合根创建唯一实例，向下注入）。
@Observable
public final class PluginFeatureStore {

    /// 当前统一状态。
    public private(set) var state: PluginFeatureState = .neverLoaded

    /// 最近一次成功快照；刷新失败且存在旧数据时保留，不清空。
    public private(set) var snapshot: PluginSnapshot?

    /// 列表投影（E2）。
    public private(set) var pluginEntries: [PluginListEntry] = []

    /// 插件详情投影（E3）。
    public private(set) var pluginDetails: [PluginDetailEntry] = []

    /// App 详情投影（E3）。
    public private(set) var applicationDetails: [ApplicationDetailEntry] = []

    /// 双向关联投影（E3 Resolver 共用输入）。
    public private(set) var associationEntries: [PluginAssociationEntry] = []

    /// 最近一次刷新失败提示；成功刷新清空。有旧数据时与 `.loaded` 并存。
    public private(set) var lastRefreshError: String?

    private let repository: any PluginRepository
    private let resolver: PluginAssociationResolver
    private let refreshProvider: () -> PluginRefreshOutcome

    private var hasStartedInitialLoad = false
    private var isRefreshing = false

    /// - Parameters:
    ///   - repository: 唯一只读仓库实例。
    ///   - refreshProvider: 刷新结果接缝；默认包装 `repository.refresh()`。
    ///     离线测试可注入失败结果覆盖 failed / 旧数据保留分支。
    public init(repository: any PluginRepository,
                refreshProvider: (() -> PluginRefreshOutcome)? = nil) {
        self.repository = repository
        self.resolver = PluginAssociationResolver()
        self.refreshProvider = refreshProvider ?? {
            .snapshot(repository.refresh())
        }
    }

    /// 初次进入插件功能时调用；守卫保证初次扫描只执行一次。
    public func loadIfNeeded() {
        guard !hasStartedInitialLoad else { return }
        hasStartedInitialLoad = true
        refresh()
    }

    /// 手动刷新入口。并发守卫：已有刷新在进行时直接返回，不重复进入。
    public func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        state = .loading
        lastRefreshError = nil

        switch refreshProvider() {
        case .snapshot(let newSnapshot):
            snapshot = newSnapshot
            rebuildProjections(from: newSnapshot)
            state = pluginEntries.isEmpty ? .empty : .loaded
        case .failure(let message):
            lastRefreshError = message
            if snapshot == nil {
                state = .failed(message)
            } else {
                // 保留旧快照与旧投影，仅记录刷新失败提示。
                state = .loaded
            }
        }

        isRefreshing = false
    }

    // MARK: - 详情查询（读缓存，不二次扫描）

    /// 按稳定 ID 取插件详情；缺失返回 nil，不生成虚构详情。
    public func pluginDetail(id: String) -> PluginDetailEntry? {
        pluginDetails.first { $0.id == id }
    }

    /// 按稳定 ID 取 App 详情；缺失返回 nil。
    public func applicationDetail(id: String) -> ApplicationDetailEntry? {
        applicationDetails.first { $0.id == id }
    }

    /// 插件方向关联（同一份关联投影，经 E3 Resolver 过滤去重保序）。
    public func associations(forPluginID pluginID: String) -> [PluginAssociationEntry] {
        resolver.associations(forPluginID: pluginID, from: associationEntries)
    }

    /// App 方向关联（同一份关联投影，经 E3 Resolver 过滤去重保序）。
    public func associations(forApplicationID applicationID: String) -> [PluginAssociationEntry] {
        resolver.associations(forApplicationID: applicationID, from: associationEntries)
    }

    // MARK: - 投影统一重建

    /// 三类投影与关联条目在单一方法内由同一份快照生成，保证列表 / 详情 /
    /// App 详情 / 关联前后同源。
    private func rebuildProjections(from snapshot: PluginSnapshot) {
        pluginEntries = PluginListProjection.entries(from: snapshot.plugins)
        pluginDetails = snapshot.plugins.compactMap { plugin in
            PluginDetailProjection.detail(forPluginID: plugin.id, snapshot: snapshot)
        }
        applicationDetails = snapshot.applications.compactMap { app in
            ApplicationDetailProjection.detail(forAppID: app.bundleID, snapshot: snapshot)
        }
        associationEntries = ApplicationDetailProjection.allAssociationEntries(from: snapshot)
    }
}
