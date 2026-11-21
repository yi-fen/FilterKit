//
//  PluginAssociationEntry.swift
//  FilterKit 0.1-E3 Plugin Detail & App Association Explorer
//
//  E1 FKPluginAssociation → 关联展示投影。不制造新的关联事实：分类沿用 E1
//  FKAssociationType，证据原值透传；globalRule 不等于 exactMatch。
//

import Foundation

public struct PluginAssociationEntry: Identifiable, Equatable, Sendable {
    public let id: String
    public let pluginID: String
    public let applicationID: String?
    public let category: FKAssociationType
    public let matchType: String
    public let isGlobal: Bool
    public let matchedAppCount: Int
    public let unmatchedTargetCount: Int
    public let evidenceDescription: String?
    public let loaded: String

    public init(id: String, pluginID: String, applicationID: String?,
                category: FKAssociationType, matchType: String, isGlobal: Bool,
                matchedAppCount: Int, unmatchedTargetCount: Int,
                evidenceDescription: String?, loaded: String) {
        self.id = id
        self.pluginID = pluginID
        self.applicationID = applicationID
        self.category = category
        self.matchType = matchType
        self.isGlobal = isGlobal
        self.matchedAppCount = matchedAppCount
        self.unmatchedTargetCount = unmatchedTargetCount
        self.evidenceDescription = evidenceDescription
        self.loaded = loaded
    }
}
