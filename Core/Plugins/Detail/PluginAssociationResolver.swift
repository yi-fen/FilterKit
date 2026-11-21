//
//  PluginAssociationResolver.swift
//  FilterKit 0.1-E3 Plugin Detail & App Association Explorer
//
//  双向关联查询：只在已投影的关联数组上过滤，不回查快照、不重新扫描、
//  不重新配对。两个浏览方向共用同一份投影输入；结果按 id 去重保序。
//

import Foundation

public struct PluginAssociationResolver: Sendable {

    public init() {}

    public func associations(forPluginID pluginID: String,
                             from entries: [PluginAssociationEntry]) -> [PluginAssociationEntry] {
        deduped(entries.filter { $0.pluginID == pluginID })
    }

    public func associations(forApplicationID applicationID: String,
                             from entries: [PluginAssociationEntry]) -> [PluginAssociationEntry] {
        deduped(entries.filter { $0.applicationID == applicationID })
    }

    public func exactMatches(forPluginID pluginID: String,
                             from entries: [PluginAssociationEntry]) -> [PluginAssociationEntry] {
        deduped(entries.filter { $0.pluginID == pluginID && $0.category == .exactMatch })
    }

    public func exactMatches(forApplicationID applicationID: String,
                             from entries: [PluginAssociationEntry]) -> [PluginAssociationEntry] {
        deduped(entries.filter { $0.applicationID == applicationID && $0.category == .exactMatch })
    }

    private func deduped(_ entries: [PluginAssociationEntry]) -> [PluginAssociationEntry] {
        var seen = Set<String>()
        return entries.filter { seen.insert($0.id).inserted }
    }
}
