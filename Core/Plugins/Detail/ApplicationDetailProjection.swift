//
//  ApplicationDetailProjection.swift
//  FilterKit 0.1-E3 Plugin Detail & App Association Explorer
//
//  FKApplication → ApplicationDetailEntry 纯映射；关联按 Bundle ID 回挂到 App，
//  只保留 E1 已建立的关联证据，不根据 Bundle ID 自行推断新关联。
//

import Foundation

public enum ApplicationDetailProjection {

    /// 快照全量关联投影，供 Resolver 两个浏览方向共用同一份输入。
    public static func allAssociationEntries(from snapshot: PluginSnapshot) -> [PluginAssociationEntry] {
        snapshot.associations.map { PluginDetailProjection.associationEntry(from: $0) }
    }

    public static func entry(from app: FKApplication,
                             associations: [FKPluginAssociation]) -> ApplicationDetailEntry {
        let mapped = associations
            .filter { $0.appBundleID == app.bundleID }
            .map { PluginDetailProjection.associationEntry(from: $0) }

        return ApplicationDetailEntry(
            id: app.bundleID,
            displayName: app.name,
            bundleIdentifier: app.bundleID,
            executable: app.executable,
            version: app.version,
            isSystem: app.isSystem,
            associations: mapped
        )
    }

    /// 经快照索引回查 App；缺失返回 nil，不生成虚构详情。
    public static func detail(forAppID id: String, snapshot: PluginSnapshot) -> ApplicationDetailEntry? {
        guard let app = snapshot.applicationByID[id] else { return nil }
        return entry(from: app, associations: snapshot.associations)
    }
}
