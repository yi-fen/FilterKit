//
//  PermissionProbeReportBuilder.swift
//  FilterKit Core — PermissionProbe 报告装配（Stage 2.4-D7）
//
//  证据数组原样归集，模型层不排序；generatedAt 由装配层写入。探针报告独立于
//  `ReportEnvelope`，不并入既有报告信封（合并需单独评审）。
//

import Foundation
import Models

/// 探针报告装配器。
public final class PermissionProbeReportBuilder {

    public init() {}

    /// 汇总证据为只读报告；不裁剪、不重排证据。
    public func build(evidence: [ProbeEvidence]) -> PermissionProbeReport {
        PermissionProbeReport(
            generatedAt: ProbeTimestamp.current(),
            evidence: evidence
        )
    }
}
