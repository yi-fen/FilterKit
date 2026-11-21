//
//  PluginBrowserViewModel.swift
//  FilterKit 0.1-E2 Plugin List & Discovery
//
//  列表查询视图模型：持有投影条目缓存，搜索 / 筛选 / 排序全部在内存查询层完成，
//  不调用 Repository、不触发扫描。Repository 与真实快照接线留 E4。
//

import Foundation
import Core

@Observable
final class PluginBrowserViewModel {

    /// 列表加载状态；empty 与 failed 严格区分。
    enum LoadState: Equatable {
        case neverLoaded
        case loading
        case loaded
        case empty
        case failed(String)
    }

    private let queryEngine: PluginListQueryEngine
    private var cachedEntries: [PluginListEntry] = []

    var searchText: String = ""
    var filter: PluginListFilter = .all
    var sort: PluginListSort = .nameAscending

    private(set) var entries: [PluginListEntry] = []
    private(set) var loadState: LoadState = .neverLoaded
    private(set) var errorMessage: String?

    init(queryEngine: PluginListQueryEngine = PluginListQueryEngine()) {
        self.queryEngine = queryEngine
    }

    /// 注入快照投影结果（E4 由 Repository 快照喂入）；注入后重放当前查询。
    func setEntries(_ entries: [PluginListEntry]) {
        cachedEntries = entries
        errorMessage = nil
        loadState = entries.isEmpty ? .empty : .loaded
        applyQuery()
    }

    func setLoading() {
        loadState = .loading
    }

    func setError(_ message: String) {
        errorMessage = message
        loadState = .failed(message)
    }

    /// 仅在内存缓存上执行查询，不触发诊断扫描。
    func applyQuery() {
        let query = PluginListQuery(searchText: searchText, filter: filter, sort: sort)
        entries = queryEngine.execute(entries: cachedEntries, query: query)
    }

    func clearFilters() {
        searchText = ""
        filter = .all
        sort = .nameAscending
        applyQuery()
    }
}
