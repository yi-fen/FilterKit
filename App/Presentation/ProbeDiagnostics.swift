//
//  ProbeDiagnostics.swift
//  FilterKit App Presentation（Stage 2.4-D7）
//
//  探针报告纯 Foundation 映射：按分类分组为诊断分区，六态映射界面分级与文案。
//  本层只消费 `PermissionProbeReport`，不触发扫描、不做私有文件访问；
//  不把 unknown / notExecuted 升级为 success。
//

import Foundation
import Models

/// 探针诊断分区映射器。
public enum ProbeDiagnosticsMapper {

    private static let categoryOrder: [ProbeCategory] = [
        .environment, .jbroot, .ellekit, .pluginFiles,
        .packageDatabase, .entitlement, .sandbox, .jbrootAPI
    ]

    public static func sections(_ report: PermissionProbeReport?) -> [DiagnosticsSection] {
        guard let report, !report.evidence.isEmpty else {
            return [
                DiagnosticsSection(
                    id: "probes",
                    title: "Permission Probes",
                    rows: [
                        DetailRow(label: "Probes", value: "No probe evidence",
                                  status: DisplayStatus(kind: .unknown, text: "Unknown"))
                    ]
                )
            ]
        }

        return categoryOrder.compactMap { category in
            let rows = report.evidence
                .filter { $0.category == category }
                .map { evidence in
                    let status = displayStatus(for: evidence.status)
                    return DetailRow(
                        label: evidence.probeID,
                        value: evidence.observedValue ?? status.text,
                        status: status
                    )
                }
            guard !rows.isEmpty else { return nil }
            return DiagnosticsSection(
                id: category.rawValue,
                title: title(for: category),
                rows: rows
            )
        }
    }

    /// 探针状态 → 展示状态分级。
    public static func displayStatus(for status: ProbeStatus) -> DisplayStatus {
        switch status {
        case .passed:
            return DisplayStatus(kind: .success, text: "Passed")
        case .failed:
            return DisplayStatus(kind: .failure, text: "Failed")
        case .permissionDenied:
            return DisplayStatus(kind: .failure, text: "Denied")
        case .unavailable:
            return DisplayStatus(kind: .warning, text: "Unavailable")
        case .notExecuted:
            return DisplayStatus(kind: .unknown, text: "Not Executed")
        case .unknown:
            return DisplayStatus(kind: .unknown, text: "Unknown")
        }
    }

    private static func title(for category: ProbeCategory) -> String {
        switch category {
        case .environment: return "Environment"
        case .jbroot: return "JBROOT"
        case .ellekit: return "ElleKit"
        case .pluginFiles: return "Plugin Files"
        case .packageDatabase: return "Package Database"
        case .entitlement: return "Entitlement"
        case .sandbox: return "Sandbox"
        case .jbrootAPI: return "RootHide API"
        }
    }
}
