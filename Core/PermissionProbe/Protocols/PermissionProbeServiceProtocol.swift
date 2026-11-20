//
//  PermissionProbeServiceProtocol.swift
//  FilterKit Core — PermissionProbe 协议接缝（Stage 2.4-D1）
//
//  探针编排接缝。D1 仅定义协议，具体装配在 D2 之后；单项探针失败不中断其他
//  探针（约束 A7）。协议只引用 Models 探针类型。
//  规格：Spec/Stage-2/Stage-2.4-D1-PermissionProbe-Foundation-Spec.md §4.2。
//

import Foundation
import Models

/// 探针编排服务。
public protocol PermissionProbeServiceProtocol {
    /// 运行已装配探针并汇总为报告。
    func runProbes() -> PermissionProbeReport
}
