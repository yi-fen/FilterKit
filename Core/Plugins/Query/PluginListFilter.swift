//
//  PluginListFilter.swift
//  FilterKit 0.1-E2 Plugin List & Discovery
//
//  列表筛选条件三维度：配置 / 关联 / 证据。loaded 属运行时状态，不进入筛选
//  维度（见规格 §2.6）。筛选作用于 E1 真实类型投影，不使用猜测字符串比较。
//

import Foundation

/// 配置状态筛选（作用于 FKPlugin.status.configured）。
public enum PluginConfigurationFilter: String, CaseIterable, Equatable, Codable {
    case all
    case configured
    case notConfigured
    case unverified
    case unknown
}

/// 关联分类筛选（作用于条目 associationCategories）。
public enum PluginAssociationFilter: String, CaseIterable, Equatable, Codable {
    case all
    case associated
    case unassociated
    case globalRule
    case unmatched
    case invalid
    case unresolved
}

/// 证据状态筛选（作用于 FKPlugin.status.installed）。
public enum PluginEvidenceFilter: String, CaseIterable, Equatable, Codable {
    case all
    case confirmed
    case absent
    case unverified
    case unknown
}

/// 列表复合筛选条件；三维 AND 组合。
public struct PluginListFilter: Equatable, Codable {
    public var configuration: PluginConfigurationFilter
    public var association: PluginAssociationFilter
    public var evidence: PluginEvidenceFilter

    public init(configuration: PluginConfigurationFilter = .all,
                association: PluginAssociationFilter = .all,
                evidence: PluginEvidenceFilter = .all) {
        self.configuration = configuration
        self.association = association
        self.evidence = evidence
    }

    public static let all = PluginListFilter()
}
