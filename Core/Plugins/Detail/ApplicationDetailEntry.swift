//
//  ApplicationDetailEntry.swift
//  FilterKit 0.1-E3 Plugin Detail & App Association Explorer
//
//  App 详情投影：associations 只代表静态关联证据，不代表 App 运行时真的
//  加载了对应插件；精确关联数量只统计 exactMatch。
//

import Foundation

public struct ApplicationDetailEntry: Identifiable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let bundleIdentifier: String
    public let executable: String?
    public let version: String?
    public let isSystem: Bool
    public let associations: [PluginAssociationEntry]

    public init(id: String, displayName: String, bundleIdentifier: String,
                executable: String?, version: String?, isSystem: Bool,
                associations: [PluginAssociationEntry]) {
        self.id = id
        self.displayName = displayName
        self.bundleIdentifier = bundleIdentifier
        self.executable = executable
        self.version = version
        self.isSystem = isSystem
        self.associations = associations
    }

    public var exactMatchCount: Int {
        associations.filter { $0.category == .exactMatch }.count
    }
}
