//
//  ProbeStatus.swift
//  FilterKit Models — PermissionProbe（Stage 2.4-D1）
//
//  探针结论六态。unavailable（资源/API 不存在）与 permissionDenied（明确权限拒绝）
//  不得合并；notExecuted 不计入 failed；unknown 不升级为 passed/failed。
//  规格：Spec/Stage-2/Stage-2.4-D1-PermissionProbe-Foundation-Spec.md §3.1。
//

import Foundation

/// 探针结论状态。
public enum ProbeStatus: String, Codable, Equatable {
    /// 探针执行并验证成功。
    case passed
    /// 检测执行失败（其他 I/O / 解析等错误）。
    case failed
    /// 明确遭遇权限拒绝。
    case permissionDenied = "permission_denied"
    /// 目标资源或 API 不存在。
    case unavailable
    /// 前置条件不满足而未执行。
    case notExecuted = "not_executed"
    /// 无法得出可靠结论。
    case unknown
}
