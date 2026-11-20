//
//  PermissionProbing.swift
//  FilterKit Core — PermissionProbe 协议接缝（Stage 2.4-D1）
//
//  单个探针的执行接缝。D1 仅定义协议，不提供具体实现；具体探针在 D2～D6 按
//  批次落地。协议只引用 Models 探针类型，不引用具体 Adapter / Scanner / Parser。
//  探针可返回多条证据（如目录存在性 + 枚举结果）；探针可抛错，由编排服务
//  捕获为保留原 probeID 的失败证据，不中断其他探针；常规错误以证据状态承载。
//  规格：Spec/Stage-2/Stage-2.4-D1-PermissionProbe-Foundation-Spec.md §4.1。
//

import Foundation
import Models

/// 单个只读探针。
public protocol PermissionProbing {
    /// 探针稳定标识，与产出证据的 `probeID` 一致。
    var probeID: String { get }

    /// 执行只读探测并返回证据数组；可抛错由编排服务捕获为失败证据，
    /// 不中断其他探针。错误以证据状态承载。
    func run() throws -> [ProbeEvidence]
}
