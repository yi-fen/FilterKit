//
//  EntitlementEvidenceSource.swift
//  FilterKit Core — PermissionProbe entitlement 证据来源分类（Stage 2.4-D5 / R2-A）
//
//  三类证据严格分离、互不替代：
//  - signed：代码签名文件中静态声明的 entitlement（签名事实，由 CodeSignInspecting 读取）；
//  - runtime：进程运行时实际生效的 entitlement 视图（进程内读取；iOS GUI 进程公开稳定
//    读取接口尚未核实，保持 unavailable/unknown，不以签名文件内容代替运行时结论）；
//  - resourceAccess：对具体资源的实际可达 / 拒绝 / 不存在（由 D2/D3/D4 目录与文件探针、
//    D5 SandboxAccessProbe 独立取证，不属于 entitlement 探针）。
//
//  本文件只定义 Core 层事实分类；冻结公共 Models（ProbeEvidence / ProbeStatus 等）
//  与 ReportEnvelope 不改动。
//

import Foundation

/// entitlement / 沙盒证据来源分类。
public enum EntitlementEvidenceSource: String, Equatable, Codable {
    /// 代码签名静态 entitlement。
    case signed
    /// 进程运行时 entitlement 视图。
    case runtime
    /// 具体资源的实际访问结果。
    case resourceAccess
}

/// 单条 entitlement 证据的 Core 层事实记录（不进入冻结 Models；探针对外仍以
/// `ProbeEvidence` 承载，本记录用于 Core 内部归类与测试断言）。
public struct EntitlementEvidenceRecord: Equatable {
    /// 证据来源。
    public var source: EntitlementEvidenceSource
    /// 检查接口是否可用并成功取得快照。
    public var available: Bool
    /// 观测到的 entitlement 键名摘要（不含值，不回显敏感材料）。
    public var observedKeys: [String]
    /// 不可用 / 受限原因；可用时为 `nil`。
    public var reason: String?

    public init(source: EntitlementEvidenceSource,
                available: Bool,
                observedKeys: [String] = [],
                reason: String? = nil) {
        self.source = source
        self.available = available
        self.observedKeys = observedKeys
        self.reason = reason
    }
}

