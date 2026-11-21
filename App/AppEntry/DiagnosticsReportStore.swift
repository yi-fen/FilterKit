//
//  DiagnosticsReportStore.swift
//  FilterKit App — R3-C Live Diagnostics Export Bridge
//
//  运行期共享的最近一次只读扫描快照。Diagnostics 扫描写入、Settings 导出读取，
//  二者共享同一数据源，避免“页面显示本次、导出上一次”的分叉。
//
//  边界：仅内存保存；不写数据库 / 文件缓存 / 持久化；不触发扫描；不回写设备。
//

import Foundation
import Core

/// 诊断扫描内存 Store（App 组合根创建唯一实例，注入 Diagnostics 与 Settings）。
@Observable
public final class DiagnosticsReportStore {
    /// 最近一次成功扫描的导出段；未成功扫描时为 nil。
    public private(set) var latestCompleted: DiagnosticsExportSection?
    /// 当前扫描状态。
    public private(set) var scanState: DiagnosticsScanState = .neverRun

    public init() {}

    /// 扫描开始（按钮显式触发）。
    public func beginScan() {
        scanState = .running
    }

    /// 扫描完成；覆盖上一次成功结果。
    public func complete(_ section: DiagnosticsExportSection) {
        latestCompleted = section
        scanState = .completed
    }

    /// 扫描失败：本次不产出条目；历史成功段仅保留时间戳用于追溯，不冒充本次结果。
    public func markFailed() {
        scanState = .failed
    }

    /// 清空快照（预留；当前流程不自动调用）。
    public func clear() {
        latestCompleted = nil
        scanState = .neverRun
    }

    /// 导出投影：按当前状态生成诊断段；未扫描 / 失败 / 进行中均为空条目。
    public func exportSection() -> DiagnosticsExportSection {
        switch scanState {
        case .completed:
            return latestCompleted ?? .neverRun()
        case .failed:
            return .failed(previousCompletedAt: latestCompleted?.generatedAt)
        case .running:
            return .running(previousCompletedAt: latestCompleted?.generatedAt)
        case .neverRun:
            return .neverRun()
        }
    }
}
