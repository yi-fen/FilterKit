//
//  FKApplication.swift
//  FilterKit 0.1-E1 Plugin Data Foundation（E1-01 App 模型）
//
//  App 侧反向索引：关联类型不折叠，类型信息保留在 FKPluginAssociation 上，
//  供后续批次分流展示精确匹配 / 全局规则 / 未匹配目标。
//

import Foundation

public struct FKApplication: Equatable, Codable, Identifiable {
    public var id: String { bundleID }
    public var bundleID: String
    public var name: String
    public var version: String?
    public var executable: String?
    public var isSystem: Bool
    /// 经关联行反向索引到的插件标识（含全部关联类型，类型不折叠）。
    public var associatedPluginIDs: [String]

    public init(bundleID: String, name: String, version: String?,
                executable: String?, isSystem: Bool,
                associatedPluginIDs: [String]) {
        self.bundleID = bundleID
        self.name = name
        self.version = version
        self.executable = executable
        self.isSystem = isSystem
        self.associatedPluginIDs = associatedPluginIDs
    }
}
