//
//  FKPlugin.swift
//  FilterKit 0.1-E1 Plugin Data Foundation（E1-01 插件聚合根）
//
// Core 只读领域模型，与信封 Models.Plugin 并存：信封模型服务导出 schema，
// 本模型服务管理器只读浏览。raw 保留插件行原始键值，供后续批次详情与证据追溯，
// Mapper 不裁剪原始证据。
//

import Foundation

public struct FKPlugin: Equatable, Codable, Identifiable {
    public var id: String
    public var name: String
    public var dylibPath: String?
    public var plistPath: String?
    public var source: FKPluginSource
    public var status: FKPluginStatus
    public var configuration: FKPluginConfiguration?
    public var associations: [FKPluginAssociation]
    public var fileSize: Int64?
    public var version: String?
    public var packageIdentifier: String?
    /// 插件行原始键值（证据保留，不参与确定性展示之外的结论推导）。
    public var raw: [String: String]

    public init(id: String, name: String, dylibPath: String?, plistPath: String?,
                source: FKPluginSource, status: FKPluginStatus,
                configuration: FKPluginConfiguration?,
                associations: [FKPluginAssociation], fileSize: Int64?,
                version: String?, packageIdentifier: String?,
                raw: [String: String]) {
        self.id = id
        self.name = name
        self.dylibPath = dylibPath
        self.plistPath = plistPath
        self.source = source
        self.status = status
        self.configuration = configuration
        self.associations = associations
        self.fileSize = fileSize
        self.version = version
        self.packageIdentifier = packageIdentifier
        self.raw = raw
    }
}
