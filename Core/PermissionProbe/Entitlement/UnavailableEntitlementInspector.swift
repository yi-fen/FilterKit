//
//  UnavailableEntitlementInspector.swift
//  FilterKit Core — PermissionProbe 占位检查器（Stage 2.4-D5）
//
//  接口未核实前的保守实现：不触碰私有 API，不伪造 entitlement 键；快照标记
//  不可用，由探针保留 unavailable/unknown 状态。真机受支持接口核实后替换
//  本实现，探针模型与协议接缝不变。
//

import Foundation

/// 进程（runtime）entitlement 占位检查器。
///
/// iOS GUI 进程内读取运行时生效 entitlement 的公开稳定接口尚未核实：Apple
/// `SecTaskCreateFromSelf` / `SecTaskCopyValueForEntitlement` 官方可用平台为
/// macOS / Mac Catalyst，不含 iOS。核实前保持不可用，不以签名文件内容代替运行时结论。
public struct UnavailableEntitlementInspector: EntitlementInspecting {
    public let reason: String

    public init(reason: String = "runtime entitlement read interface not verified on iOS GUI process (SecTask APIs macOS/Catalyst only)") {
        self.reason = reason
    }

    public func inspectProcessEntitlements() -> EntitlementSnapshot {
        EntitlementSnapshot(available: false, reason: reason)
    }
}

/// 代码签名（signed）entitlement 占位检查器。
public struct UnavailableCodeSignInspector: CodeSignInspecting {
    public let reason: String

    public init(reason: String = "code-sign entitlement inspection interface not verified") {
        self.reason = reason
    }

    public func inspectCodeSignEntitlements() -> EntitlementSnapshot {
        EntitlementSnapshot(available: false, reason: reason)
    }
}
