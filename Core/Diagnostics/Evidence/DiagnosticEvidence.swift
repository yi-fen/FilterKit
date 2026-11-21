//
//  DiagnosticEvidence.swift
//  FilterKit Stage 2.6 R3-A7 — 内部证据记录（D-R2-04）
//
//  内部诊断数据结构：不加入公共 Models，不改现有 JSON 信封字段。
//  对外仍经既有 `FKDiagnosticFinding` / `[[String:String]]` 段输出；
//  本结构只在引擎内部与离线校验用例之间传递。
//

import Foundation

struct DiagnosticEvidence: Equatable {
    /// 证据等级。
    let level: DiagnosticEvidenceLevel
    /// 证据来源：runtime_image / dpkg_status / static_filesystem / static_filter_match_only /
    /// synthetic_preview / insufficient 等既有口径。
    let source: String
    /// 被观测到的取值（可空：无观测值时保持 nil，不写空串冒充结论）。
    let observedValue: String?
    /// 补充说明（可空）。
    let reason: String?
    /// 记录时间戳。
    let timestamp: Date

    init(level: DiagnosticEvidenceLevel,
         source: String,
         observedValue: String? = nil,
         reason: String? = nil,
         timestamp: Date = Date()) {
        self.level = level
        self.source = source
        self.observedValue = observedValue
        self.reason = reason
        self.timestamp = timestamp
    }
}
