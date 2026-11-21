//
//  DiagnosticsReportMapper.swift
//  FilterKit Core — R3-C Live Diagnostics Export Bridge
//
//  把引擎只读报告 `FKDiagnosticReport` 投影为独立导出段 `DiagnosticsExportSection`。
//  纯映射：不访问文件系统、不重新扫描、不补全状态；原始行键值整体进入 payload。
//

import Foundation

/// 引擎报告 → 诊断导出段映射器。
public enum DiagnosticsReportMapper {

    /// 类别与主标识 / 状态键的对应口径（与引擎行字段一致）。
    private struct CategoryMapping {
        let category: String
        let labelKey: String
        let statusKey: String?
    }

    private static let rowMappings: [CategoryMapping] = [
        CategoryMapping(category: "roots", labelKey: "path", statusKey: "status"),
        CategoryMapping(category: "dynamicLibraries", labelKey: "path", statusKey: "enumerable"),
        CategoryMapping(category: "plugins", labelKey: "name", statusKey: "source"),
        CategoryMapping(category: "filters", labelKey: "plugin", statusKey: "parse_status"),
        CategoryMapping(category: "injectorEvidence", labelKey: "type", statusKey: "scope"),
        CategoryMapping(category: "packages", labelKey: "package_id", statusKey: "status"),
        CategoryMapping(category: "fileOwnership", labelKey: "path", statusKey: nil),
        CategoryMapping(category: "integrity", labelKey: "path", statusKey: "status"),
        CategoryMapping(category: "helperCandidates", labelKey: "path", statusKey: "executable"),
        CategoryMapping(category: "helperRegistrations", labelKey: "label", statusKey: "program_exists"),
        CategoryMapping(category: "applications", labelKey: "name", statusKey: "version"),
        CategoryMapping(category: "associations", labelKey: "plugin", statusKey: "match_type")
    ]

    /// 将引擎报告映射为完成态导出段。空报告映射为 completed + 空条目，与失败态区分。
    public static func section(from report: FKDiagnosticReport) -> DiagnosticsExportSection {
        var items: [DiagnosticsExportItem] = []

        for mapping in rowMappings {
            let rows = rows(for: mapping.category, in: report)
            for (index, row) in rows.enumerated() {
                items.append(makeItem(category: mapping.category,
                                      index: index,
                                      labelKey: mapping.labelKey,
                                      statusKey: mapping.statusKey,
                                      row: row))
            }
        }

        for (index, finding) in report.findings.enumerated() {
            let item = DiagnosticsExportItem(
                id: "finding:\(index)",
                category: "finding",
                title: finding.title,
                status: finding.state,
                detail: finding.detail,
                payload: finding.payload
            )
            items.append(item)
        }

        return DiagnosticsExportSection(
            scanState: .completed,
            generatedAt: report.generatedAt,
            environment: report.environment,
            items: items,
            previousCompletedAt: nil
        )
    }

    // MARK: - Private

    private static func rows(for category: String, in report: FKDiagnosticReport) -> [[String: String]] {
        switch category {
        case "roots": return report.roots
        case "dynamicLibraries": return report.dynamicLibraryDirectories
        case "plugins": return report.plugins
        case "filters": return report.filters
        case "injectorEvidence": return report.injectorEvidence
        case "packages": return report.packages
        case "fileOwnership": return report.fileOwnership
        case "integrity": return report.integrity
        case "helperCandidates": return report.helperCandidates
        case "helperRegistrations": return report.helperRegistrations
        case "applications": return report.applications
        case "associations": return report.associations
        default: return []
        }
    }

    private static func makeItem(category: String,
                                 index: Int,
                                 labelKey: String,
                                 statusKey: String?,
                                 row: [String: String]) -> DiagnosticsExportItem {
        let title = row[labelKey]?.isEmpty == false ? row[labelKey]! : "Unknown"
        let status = statusKey.flatMap { row[$0] }.flatMap { $0.isEmpty ? nil : $0 }

        let reservedKeys: Set<String> = [labelKey]
        let detailKeys = row.keys
            .filter { !reservedKeys.contains($0) && $0 != (statusKey ?? "") }
            .sorted()
        let detail = detailKeys.isEmpty ? nil : detailKeys
            .map { "\($0)=\(row[$0] ?? "")" }
            .joined(separator: " · ")

        return DiagnosticsExportItem(
            id: "\(category):\(index)",
            category: category,
            title: title,
            status: status,
            detail: detail,
            payload: row
        )
    }
}
