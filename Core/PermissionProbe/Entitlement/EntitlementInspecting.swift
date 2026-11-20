//
//  EntitlementInspecting.swift
//  FilterKit Core — PermissionProbe entitlement 检查接缝（Stage 2.4-D5）
//
//  进程 entitlement 与代码签名 entitlement 检查接缝。当前 iOS 环境下可用于
//  可靠读取进程 entitlement 的受支持接口尚未核实：未确认前默认实现返回
//  `available = false`，探针落 unavailable/unknown；不调用未验证私有 API，
//  不把 entitlement 字典中存在某键当作权限放行证明。
//

import Foundation
import Models

/// entitlement 检查快照（只读事实位）。
public struct EntitlementSnapshot: Equatable {
    /// 检查接口是否可用并成功取得快照。
    public var available: Bool
    /// 观测到的 entitlement 键名摘要（不含值，不回显敏感材料）。
    public var observedKeys: [String]
    /// 不可用/受限原因；可用时为 `nil`。
    public var reason: String?

    public init(available: Bool,
                observedKeys: [String] = [],
                reason: String? = nil) {
        self.available = available
        self.observedKeys = observedKeys
        self.reason = reason
    }
}

/// 进程 entitlement 检查接缝。
public protocol EntitlementInspecting {
    func inspectProcessEntitlements() -> EntitlementSnapshot
}

/// 代码签名 entitlement 检查接缝。
public protocol CodeSignInspecting {
    func inspectCodeSignEntitlements() -> EntitlementSnapshot
}
