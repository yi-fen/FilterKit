//
//  FKPluginAssociation.swift
//  FilterKit 0.1-E1 Plugin Data Foundation（E1-01 关联模型）
//
//  关联分类沿用诊断引擎既有 category 词表，不另造规则：
//  - exactMatch 才计入精确关联数量；
//  - globalRule 单独展示；
//  - unmatchedTarget 不冒充已关联；
//  - invalidConfiguration 不当有效注入规则；
//  - 静态匹配 ≠ 实际注入成功；关联证据不升级为 verified。
//

import Foundation

/// 插件 ↔ App 关联类型（与引擎 category 原值一一对应）。
public enum FKAssociationType: String, Codable, Equatable {
    case exactMatch = "exact_match"
    case globalRule = "global"
    case unmatchedTarget = "unmatched_target"
    case invalidConfiguration = "invalid_configuration"
    case unresolved = "unresolved_non_bundle_rule"

    /// 引擎 category 原值 → 关联类型；未识别词表归入 unresolved，不丢证据。
    public static func from(category: String?) -> FKAssociationType {
        guard let category, let value = FKAssociationType(rawValue: category) else {
            return .unresolved
        }
        return value
    }
}

public struct FKPluginAssociation: Equatable, Codable, Identifiable {
    public var id: String { "\(pluginID)|\(appBundleID ?? "")|\(matchType)" }
    /// 回挂到的插件标识；未命中插件行时保留引擎 plugin 标签原值。
    public var pluginID: String
    /// 关联 App 的 Bundle ID；无匹配 App 时为 nil。
    public var appBundleID: String?
    /// 引擎 match_type 原值（bundle / executable / none）。
    public var matchType: String
    /// 关联分类。
    public var type: FKAssociationType
    public var isGlobal: Bool
    public var matchedAppCount: Int
    public var unmatchedTargetCount: Int
    /// 证据标注原值（static_filter_match_only）。
    public var evidence: String
    /// 运行时加载状态原值；本轮恒 "unknown"。
    public var loaded: String

    public init(pluginID: String, appBundleID: String?, matchType: String,
                type: FKAssociationType, isGlobal: Bool, matchedAppCount: Int,
                unmatchedTargetCount: Int, evidence: String, loaded: String) {
        self.pluginID = pluginID
        self.appBundleID = appBundleID
        self.matchType = matchType
        self.type = type
        self.isGlobal = isGlobal
        self.matchedAppCount = matchedAppCount
        self.unmatchedTargetCount = unmatchedTargetCount
        self.evidence = evidence
        self.loaded = loaded
    }
}
