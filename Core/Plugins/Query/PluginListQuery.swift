//
//  PluginListQuery.swift
//  FilterKit 0.1-E2 Plugin List & Discovery
//
//  用户当前查询条件快照；Query 本身不执行文件扫描，也不修改 Repository。
//

import Foundation

public struct PluginListQuery: Equatable {
    public var searchText: String
    public var filter: PluginListFilter
    public var sort: PluginListSort

    public init(searchText: String = "",
                filter: PluginListFilter = .all,
                sort: PluginListSort = .nameAscending) {
        self.searchText = searchText
        self.filter = filter
        self.sort = sort
    }

    public static let empty = PluginListQuery()
}
