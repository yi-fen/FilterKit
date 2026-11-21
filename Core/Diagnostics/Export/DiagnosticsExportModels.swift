//
//  DiagnosticsExportModels.swift
//  FilterKit Core — R3-C Live Diagnostics Export Bridge
//
//  诊断段独立 Codable 导出模型。路线 A 只把引擎只读扫描结果并入既有信封导出，
//  不改公共 Models、不改信封既有字段、不重构 ReportService。
//
//  冻结口径：
//  - 未扫描 / 扫描失败 / 扫描成功但结果为空三者必须可区分；
//  - 未扫描与失败段不得生成 Preview/Broken/Orphan 等替代数据；
//  - 运行时 loaded 无独立证据时恒为 unknown，本层不做推断；
//  - 引擎原始行键值完整保留在 `payload`，映射投影不得丢字段。
//

import Foundation

/// 诊断扫描状态（App 内存 Store 与导出段共用）。
public enum DiagnosticsScanState: String, Codable, Equatable {
    /// 从未触发扫描。
    case neverRun
    /// 扫描进行中。
    case running
    /// 扫描完成（允许结果为空；空结果与失败状态分开记录）。
    case completed
    /// 扫描失败；本次结果不得用历史成功结果冒充。
    case failed
}

/// 诊断导出条目：一条引擎行（或一条 finding）的确定性投影。
///
/// `title` / `status` / `detail` 为界面与报告可读字段；`payload` 保留引擎原始
/// 全部键值，导出往返后不得裁剪。
public struct DiagnosticsExportItem: Codable, Equatable, Identifiable {
    /// 稳定条目标识：`<category>:<index>`。
    public let id: String
    /// 条目类别（roots / plugins / filters / findings …）。
    public let category: String
    /// 可读标题（路径 / 名称 / 标题等主标识）。
    public let title: String
    /// 可读状态（可空：无状态口径时保持 nil，不写空串冒充结论）。
    public let status: String?
    /// 补充说明（可空）。
    public let detail: String?
    /// 引擎原始行全量键值。
    public let payload: [String: String]

    public init(id: String,
                category: String,
                title: String,
                status: String?,
                detail: String?,
                payload: [String: String]) {
        self.id = id
        self.category = category
        self.title = title
        self.status = status
        self.detail = detail
        self.payload = payload
    }
}

/// 信封外追加的 `diagnostics` 扩展段。
///
/// 顶层信封字段保持原样；本段作为新增扩展键并入单文件 JSON。
public struct DiagnosticsExportSection: Codable, Equatable {
    /// 诊断段结构版本。
    public static let schemaVersion: Int = 1
    /// 证据范围：本桥接只做只读诊断。
    public static let evidenceScope = "read-only"

    public let schemaVersion: Int
    public let evidenceScope: String
    public let scanState: DiagnosticsScanState
    /// 本次扫描生成时间；未扫描 / 失败时为 nil。
    public let generatedAt: Date?
    /// 引擎环境键值（os_version / architecture / jbroot / route …）。
    public let environment: [String: String]
    /// 诊断条目；未扫描与失败时为空数组。
    public let items: [DiagnosticsExportItem]
    /// 上一次成功扫描的时间戳；仅用于追溯，不代表本次结果。
    public let previousCompletedAt: Date?

    public init(schemaVersion: Int = DiagnosticsExportSection.schemaVersion,
                evidenceScope: String = DiagnosticsExportSection.evidenceScope,
                scanState: DiagnosticsScanState,
                generatedAt: Date?,
                environment: [String: String],
                items: [DiagnosticsExportItem],
                previousCompletedAt: Date? = nil) {
        self.schemaVersion = schemaVersion
        self.evidenceScope = evidenceScope
        self.scanState = scanState
        self.generatedAt = generatedAt
        self.environment = environment
        self.items = items
        self.previousCompletedAt = previousCompletedAt
    }

    /// 从未扫描：空环境、空条目、无时间戳。
    public static func neverRun() -> DiagnosticsExportSection {
        DiagnosticsExportSection(scanState: .neverRun,
                                 generatedAt: nil,
                                 environment: [:],
                                 items: [],
                                 previousCompletedAt: nil)
    }

    /// 扫描失败：本次条目为空；`previousCompletedAt` 仅追溯历史成功时间。
    public static func failed(previousCompletedAt: Date?) -> DiagnosticsExportSection {
        DiagnosticsExportSection(scanState: .failed,
                                 generatedAt: nil,
                                 environment: [:],
                                 items: [],
                                 previousCompletedAt: previousCompletedAt)
    }

    /// 扫描进行中：不导出半成品条目；`previousCompletedAt` 仅追溯历史成功时间。
    public static func running(previousCompletedAt: Date?) -> DiagnosticsExportSection {
        DiagnosticsExportSection(scanState: .running,
                                 generatedAt: nil,
                                 environment: [:],
                                 items: [],
                                 previousCompletedAt: previousCompletedAt)
    }
}
