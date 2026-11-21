//
//  PluginListQueryEngine.swift
//  FilterKit 0.1-E2 Plugin List & Discovery
//
//  纯内存、无状态、无副作用：搜索 → 条件筛选 → 排序。不访问文件系统、不触发
//  扫描、不持有 Repository；重复查询同一缓存条目数组结果确定。
//

import Foundation

public struct PluginListQueryEngine {

    public init() {}

    public func execute(entries: [PluginListEntry], query: PluginListQuery) -> [PluginListEntry] {
        let searched = entries.filter { matchesSearch($0, text: query.searchText) }
        let filtered = searched.filter { matchesFilter($0, filter: query.filter) }
        return sort(filtered, by: query.sort)
    }

    // MARK: - 搜索

    private func matchesSearch(_ entry: PluginListEntry, text: String) -> Bool {
        let keyword = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return true }
        let normalizedKeyword = normalize(keyword)
        let searchable = [entry.displayName, entry.fileName, entry.filePath]
            + entry.bundleIdentifiers + entry.searchTokens
        return searchable.contains { normalize($0).contains(normalizedKeyword) }
    }

    private func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    // MARK: - 筛选

    private func matchesFilter(_ entry: PluginListEntry, filter: PluginListFilter) -> Bool {
        configurationMatches(entry, filter.configuration)
            && associationMatches(entry, filter.association)
            && evidenceMatches(entry, filter.evidence)
    }

    private func configurationMatches(_ entry: PluginListEntry, _ filter: PluginConfigurationFilter) -> Bool {
        switch filter {
        case .all: true
        case .configured: entry.configured == .confirmed
        case .notConfigured: entry.configured == .absent
        case .unverified: entry.configured == .unverified
        case .unknown: entry.configured == .unknown
        }
    }

    private func associationMatches(_ entry: PluginListEntry, _ filter: PluginAssociationFilter) -> Bool {
        let categories = entry.associationCategories
        switch filter {
        case .all: true
        case .associated: categories.contains(.exactMatch)
        case .unassociated: categories.isEmpty
        case .globalRule: categories.contains(.globalRule)
        case .unmatched: categories.contains(.unmatchedTarget)
        case .invalid: categories.contains(.invalidConfiguration)
        case .unresolved: categories.contains(.unresolved)
        }
    }

    private func evidenceMatches(_ entry: PluginListEntry, _ filter: PluginEvidenceFilter) -> Bool {
        switch filter {
        case .all: true
        case .confirmed: entry.installed == .confirmed
        case .absent: entry.installed == .absent
        case .unverified: entry.installed == .unverified
        case .unknown: entry.installed == .unknown
        }
    }

    // MARK: - 排序

    private func sort(_ entries: [PluginListEntry], by sort: PluginListSort) -> [PluginListEntry] {
        switch sort {
        case .nameAscending:
            return entries.sorted {
                $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
            }
        case .nameDescending:
            return entries.sorted {
                $0.displayName.localizedStandardCompare($1.displayName) == .orderedDescending
            }
        case .evidence:
            // 内部扩展项：证据等级排序优先级待 E3/E4 确认，暂稳定保留原序。
            return entries
        }
    }
}
