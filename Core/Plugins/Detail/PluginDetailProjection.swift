//
//  PluginDetailProjection.swift
//  FilterKit 0.1-E3 Plugin Detail & App Association Explorer
//
//  FKPlugin → PluginDetailEntry 纯映射；关联行映射在此统一落点，App 详情投影
//  复用同一映射。原始 raw 证据不在投影层裁剪，E3 不展示的键保留在 E1 模型。
//

import Foundation

public enum PluginDetailProjection {

    public static func associationEntry(from association: FKPluginAssociation) -> PluginAssociationEntry {
        PluginAssociationEntry(
            id: association.id,
            pluginID: association.pluginID,
            applicationID: nonEmpty(association.appBundleID),
            category: association.type,
            matchType: association.matchType,
            isGlobal: association.isGlobal,
            matchedAppCount: association.matchedAppCount,
            unmatchedTargetCount: association.unmatchedTargetCount,
            evidenceDescription: nonEmpty(association.evidence),
            loaded: association.loaded
        )
    }

    public static func entry(from plugin: FKPlugin) -> PluginDetailEntry {
        let fileName = baseName(plugin.dylibPath)
            ?? baseName(plugin.plistPath)
            ?? plugin.name
        let filePath = plugin.dylibPath ?? plugin.plistPath ?? ""
        let packageIdentifier = plugin.packageIdentifier ?? plugin.source.packageIdentifier

        return PluginDetailEntry(
            id: plugin.id,
            displayName: plugin.name,
            fileName: fileName,
            filePath: filePath,
            installed: plugin.status.installed,
            configured: plugin.status.configured,
            loaded: plugin.status.loaded,
            fileSize: plugin.fileSize,
            fileHash: nonEmpty(plugin.raw["hash"]),
            version: plugin.version,
            packageIdentifier: packageIdentifier,
            packageOwners: plugin.source.packageOwners,
            sourceRaw: plugin.source.raw,
            sourceEvidence: plugin.source.evidence,
            parseStatus: plugin.configuration?.parseStatus,
            isGlobalRule: plugin.configuration?.isGlobalRule ?? false,
            integrityState: .unknown,
            associations: plugin.associations.map { associationEntry(from: $0) }
        )
    }

    /// 经快照索引回查插件；缺失返回 nil，不生成虚构详情。
    public static func detail(forPluginID id: String, snapshot: PluginSnapshot) -> PluginDetailEntry? {
        guard let plugin = snapshot.pluginByID[id] else { return nil }
        return entry(from: plugin)
    }

    private static func baseName(_ path: String?) -> String? {
        guard let path, !path.isEmpty else { return nil }
        let base = (path as NSString).lastPathComponent
        return base.isEmpty ? nil : base
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}
