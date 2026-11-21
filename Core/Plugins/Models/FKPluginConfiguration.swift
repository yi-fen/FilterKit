//
//  FKPluginConfiguration.swift
//  FilterKit 0.1-E1 Plugin Data Foundation（E1-01 Filter 配置模型）
//
//  插件文件信息与注入配置分开建模：一个 dylib 可以存在但没有 Filter 规则，
//  一个 Filter 规则也可能对应缺失的 dylib。isGlobalRule 仅用于展示规则类型，
//  不计入精确 App 关联数量。
//

import Foundation

public struct FKPluginConfiguration: Equatable, Codable {
    /// Filter.plist 路径（plist_path）。
    public var filterPath: String?
    /// 命中的 Bundle ID 列表。
    public var bundles: [String]
    /// 命中的可执行文件列表。
    public var executables: [String]
    /// Classes 规则列表。
    public var classes: [String]
    /// 其余顶层键列表（other_keys）。
    public var otherKeys: [String]
    /// 是否全局规则（global == "true"）。
    public var isGlobalRule: Bool
    /// parse_status 原值（read_failed / type_mismatch / parsed / not_parsed 等）。
    public var parseStatus: String?
    /// 配置侧证据等级，与 FKPluginStatus.configured 同口径。
    public var evidence: FKPluginState

    public init(filterPath: String?, bundles: [String], executables: [String],
                classes: [String], otherKeys: [String], isGlobalRule: Bool,
                parseStatus: String?, evidence: FKPluginState) {
        self.filterPath = filterPath
        self.bundles = bundles
        self.executables = executables
        self.classes = classes
        self.otherKeys = otherKeys
        self.isGlobalRule = isGlobalRule
        self.parseStatus = parseStatus
        self.evidence = evidence
    }
}
