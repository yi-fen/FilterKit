//
//  PluginDetailEntry.swift
//  FilterKit 0.1-E3 Plugin Detail & App Association Explorer
//
//  插件详情投影：不替代 FKPlugin，也不改变原始诊断报告。三态原样透传；
//  精确关联数量只统计 exactMatch；未链接的完整性/Hash 证据保持 nil/unknown，
//  不在投影层推断。
//

import Foundation

public struct PluginDetailEntry: Identifiable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let fileName: String
    public let filePath: String
    public let installed: FKPluginState
    public let configured: FKPluginState
    public let loaded: FKPluginState
    public let fileSize: Int64?
    public let fileHash: String?
    public let version: String?
    public let packageIdentifier: String?
    public let packageOwners: [String]
    public let sourceRaw: String
    public let sourceEvidence: String?
    public let parseStatus: String?
    public let isGlobalRule: Bool
    /// E1 快照未链接插件级完整性记录，本轮恒 unknown；完整性行接入留 E4。
    public let integrityState: FKPluginState
    public let associations: [PluginAssociationEntry]

    public init(id: String, displayName: String, fileName: String, filePath: String,
                installed: FKPluginState, configured: FKPluginState, loaded: FKPluginState,
                fileSize: Int64?, fileHash: String?, version: String?,
                packageIdentifier: String?, packageOwners: [String],
                sourceRaw: String, sourceEvidence: String?, parseStatus: String?,
                isGlobalRule: Bool, integrityState: FKPluginState,
                associations: [PluginAssociationEntry]) {
        self.id = id
        self.displayName = displayName
        self.fileName = fileName
        self.filePath = filePath
        self.installed = installed
        self.configured = configured
        self.loaded = loaded
        self.fileSize = fileSize
        self.fileHash = fileHash
        self.version = version
        self.packageIdentifier = packageIdentifier
        self.packageOwners = packageOwners
        self.sourceRaw = sourceRaw
        self.sourceEvidence = sourceEvidence
        self.parseStatus = parseStatus
        self.isGlobalRule = isGlobalRule
        self.integrityState = integrityState
        self.associations = associations
    }

    /// 仅 `.exactMatch` 计入精确关联数量；全局规则不计入。
    public var exactMatchCount: Int {
        count(of: .exactMatch)
    }

    public func count(of category: FKAssociationType) -> Int {
        associations.filter { $0.category == category }.count
    }
}
