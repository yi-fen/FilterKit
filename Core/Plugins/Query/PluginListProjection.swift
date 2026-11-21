//
//  PluginListProjection.swift
//  FilterKit 0.1-E2 Plugin List & Discovery
//
//  FKPlugin → PluginListEntry 纯映射。原始 raw 证据不在投影层丢弃：E3 详情经
//  快照 pluginByID 回查原始记录；本层只承载列表查询所需字段。
//

import Foundation

public enum PluginListProjection {

    public static func entries(from plugins: [FKPlugin]) -> [PluginListEntry] {
        plugins.map { entry(from: $0) }
    }

    public static func entry(from plugin: FKPlugin) -> PluginListEntry {
        let fileName = baseName(plugin.dylibPath)
            ?? baseName(plugin.plistPath)
            ?? plugin.name
        let filePath = plugin.dylibPath ?? plugin.plistPath ?? ""

        let associatedBundleIDs = plugin.associations.compactMap { association in
            association.appBundleID.flatMap { $0.isEmpty ? nil : $0 }
        }
        let bundleIdentifiers = Array(
            Set(associatedBundleIDs + [plugin.packageIdentifier].compactMap { $0 })
        ).sorted()

        let categories = Set(plugin.associations.map { $0.type })
        let exactMatchCount = plugin.associations.filter { $0.type == .exactMatch }.count

        let tokens = [
            plugin.name,
            fileName,
            plugin.packageIdentifier,
            plugin.source.raw,
            plugin.version
        ].compactMap { $0?.isEmpty == false ? $0 : nil }

        return PluginListEntry(
            id: plugin.id,
            displayName: plugin.name,
            fileName: fileName,
            filePath: filePath,
            version: plugin.version,
            packageIdentifier: plugin.packageIdentifier,
            bundleIdentifiers: bundleIdentifiers,
            installed: plugin.status.installed,
            configured: plugin.status.configured,
            loaded: plugin.status.loaded,
            associationCategories: categories,
            exactMatchCount: exactMatchCount,
            searchTokens: tokens
        )
    }

    private static func baseName(_ path: String?) -> String? {
        guard let path, !path.isEmpty else { return nil }
        let base = (path as NSString).lastPathComponent
        return base.isEmpty ? nil : base
    }
}
