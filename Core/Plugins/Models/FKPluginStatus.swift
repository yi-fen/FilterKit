//
//  FKPluginStatus.swift
//  FilterKit 0.1-E1 Plugin Data Foundation（E1-02 三态模型）
//
//  installed / configured / loaded 三个状态互相独立：
//  - 文件存在 ≠ Filter 匹配 ≠ 运行时加载；
//  - configured 为 confirmed 不得把 loaded 自动置为 confirmed；
//  - loaded 无独立运行时证据时恒为 unknown；
//  - unknown / unverified 不等于失败，展示层不得统一降级为错误配色。
//
// 本文件只描述只读领域状态，不访问文件系统、不触发扫描。
//

import Foundation

/// 单条状态证据等级。
public enum FKPluginState: String, Codable, Equatable {
    /// 有明确正向证据。
    case confirmed
    /// 有明确缺失证据（条目存在但标记不存在，或无对应配置行）。
    case absent
    /// 证据整体缺失，不下结论。
    case unknown
    /// 条目存在但证据未通过校验（如 plist 读取失败 / 类型不符）。
    case unverified
}

/// 插件三态只读状态模型。
public struct FKPluginStatus: Equatable, Codable {
    /// 文件侧：dylib 是否在位。
    public var installed: FKPluginState
    /// 配置侧：Filter 规则是否存在且通过校验。
    public var configured: FKPluginState
    /// 运行时侧：进程内是否实际加载（本轮恒 unknown）。
    public var loaded: FKPluginState

    public init(installed: FKPluginState, configured: FKPluginState,
                loaded: FKPluginState) {
        self.installed = installed
        self.configured = configured
        self.loaded = loaded
    }
}
