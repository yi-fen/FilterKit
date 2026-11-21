//
//  PluginListEntry.swift
//  FilterKit 0.1-E2 Plugin List & Discovery
//
//  列表投影模型：不替代 E1 FKPlugin，也不改变原始诊断报告。三态原样透传
//  （不合并、不升级）；精确关联数量只统计 exactMatch。
//

import Foundation

public struct PluginListEntry: Identifiable, Equatable, Codable {
    public let id: String
    public let displayName: String
    public let fileName: String
    public let filePath: String
    public let version: String?
    public let packageIdentifier: String?
    public let bundleIdentifiers: [String]
    public let installed: FKPluginState
    public let configured: FKPluginState
    public let loaded: FKPluginState
    public let associationCategories: Set<FKAssociationType>
    public let exactMatchCount: Int
    public let searchTokens: [String]

    public init(id: String, displayName: String, fileName: String, filePath: String,
                version: String?, packageIdentifier: String?,
                bundleIdentifiers: [String],
                installed: FKPluginState, configured: FKPluginState,
                loaded: FKPluginState,
                associationCategories: Set<FKAssociationType>,
                exactMatchCount: Int, searchTokens: [String]) {
        self.id = id
        self.displayName = displayName
        self.fileName = fileName
        self.filePath = filePath
        self.version = version
        self.packageIdentifier = packageIdentifier
        self.bundleIdentifiers = bundleIdentifiers
        self.installed = installed
        self.configured = configured
        self.loaded = loaded
        self.associationCategories = associationCategories
        self.exactMatchCount = exactMatchCount
        self.searchTokens = searchTokens
    }
}
