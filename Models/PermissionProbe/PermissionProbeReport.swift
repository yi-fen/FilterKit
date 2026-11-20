//
//  PermissionProbeReport.swift
//  FilterKit Models — PermissionProbe（Stage 2.4-D1）
//
//  探针汇总报告。证据数组顺序由产出方保持，模型层不排序；generatedAt 不参与
//  确定性比较。派生统计为只读计算属性，不编码进 JSON。
//  规格：Spec/Stage-2/Stage-2.4-D1-PermissionProbe-Foundation-Spec.md §3.4。
//

import Foundation

/// 探针汇总报告。
public struct PermissionProbeReport: Codable, Equatable {
    /// 报告模型版本。
    public var schemaVersion: Int
    /// 生成时刻字符串；不参与确定性比较。
    public var generatedAt: String?
    /// 探针证据数组。
    public var evidence: [ProbeEvidence]

    public init(schemaVersion: Int = 1,
                generatedAt: String? = nil,
                evidence: [ProbeEvidence] = []) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.evidence = evidence
    }

    // MARK: - 派生统计（只读，不编码）

    public var totalCount: Int { evidence.count }

    public var passedCount: Int { count(of: .passed) }

    public var failedCount: Int { count(of: .failed) }

    public var deniedCount: Int { count(of: .permissionDenied) }

    public var unavailableCount: Int { count(of: .unavailable) }

    public var notExecutedCount: Int { count(of: .notExecuted) }

    public var unknownCount: Int { count(of: .unknown) }

    private func count(of status: ProbeStatus) -> Int {
        evidence.filter { $0.status == status }.count
    }
}
