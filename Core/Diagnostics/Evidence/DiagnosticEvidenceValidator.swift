//
//  DiagnosticEvidenceValidator.swift
//  FilterKit Stage 2.6 R3-A8 — 证据一致性校验（D-R2-04，E-01～E-09）
//
//  纯内部校验器：不写文件、不改报告信封、不新增公共字段。校验输入为既有
//  报告段与内部证据三元组；违规以规则编号 + 消息返回，由引擎经既有
//  `FKDiagnosticFinding` 通道输出。规则不写成状态间的硬性蕴含：未来若出现
//  独立运行时证据，仍按真实证据来源判断。
//

import Foundation

struct DiagnosticEvidenceValidator {

    struct Violation: Equatable {
        let rule: String
        let message: String
    }

    // MARK: E-01 / E-02 / E-03 / E-09 — 安装 / 配置 / 加载三元组

    /// 校验 installed → configured → loaded 证据链。
    /// - E-01：configured 不得仅凭 installed 记录推导为 confirmed。
    /// - E-02：loaded=confirmed 必须有 confirmed 的配置证据。
    /// - E-03：静态文件/匹配证据不能确认 loaded。
    /// - E-09：缺少运行时镜像证据时 loaded 必须保持 unknown。
    static func validateTriple(installed: DiagnosticEvidence,
                               configured: DiagnosticEvidence,
                               loaded: DiagnosticEvidence) -> [Violation] {
        var violations: [Violation] = []

        if configured.level == .confirmed && configured.source == "derived_from_installed" {
            violations.append(Violation(rule: "E-01",
                                        message: "configured 不得由 installed 记录自动推导为 confirmed"))
        }
        if loaded.level == .confirmed && configured.level != .confirmed {
            violations.append(Violation(rule: "E-02",
                                        message: "loaded=confirmed 缺少 confirmed 的配置证据"))
        }
        if loaded.level == .confirmed && loaded.source != "runtime_image" {
            violations.append(Violation(rule: "E-03",
                                        message: "静态文件/匹配证据不能确认 loaded"))
        }
        if loaded.source != "runtime_image" && loaded.level != .unknown {
            violations.append(Violation(rule: "E-09",
                                        message: "缺少运行时镜像证据时 loaded 必须保持 unknown"))
        }

        _ = installed
        return violations
    }

    // MARK: E-04 — 完整性记录

    /// 无 MD5 记录的文件不得被判定为损坏 / hard failure。
    static func validateIntegrity(_ rows: [[String: String]]) -> [Violation] {
        rows.compactMap { row in
            let status = row["status"] ?? ""
            let disposition = row["disposition"] ?? ""
            guard status == "no_checksum_record",
                  disposition == "hard_failure" || disposition == "corrupted" else { return nil }
            return Violation(rule: "E-04", message: "无 MD5 记录不得判定文件损坏")
        }
    }

    // MARK: E-05 — 访问可达性

    /// 权限拒绝 / 不可访问不得合并为「不存在」。
    static func validateAccessRecords(_ rows: [[String: String]]) -> [Violation] {
        rows.compactMap { row in
            let state = ((row["status"] ?? "") + " " + (row["error"] ?? "") + " " +
                         (row["read_status"] ?? "")).lowercased()
            let looksDenied = state.contains("permission") || state.contains("denied") || state.contains("unavailable")
            let recordedAbsent = row["status"] == "not_found" || row["exists"] == "false"
            guard looksDenied && recordedAbsent else { return nil }
            return Violation(rule: "E-05", message: "不可访问不得等同不存在")
        }
    }

    // MARK: E-06 — 注入器兼容性

    /// 未知注入器不得直接标记为不兼容。
    static func validateInjectors(_ rows: [[String: String]]) -> [Violation] {
        rows.compactMap { row in
            guard (row["type"] ?? "unknown") == "unknown",
                  row["compatibility"] == "incompatible" else { return nil }
            return Violation(rule: "E-06", message: "未知注入器不得直接判定不兼容")
        }
    }

    // MARK: E-07 / E-08 — 静态关联

    /// E-07：global 规则不得计入 exact_match。
    /// E-08：静态关联缺少运行时证据时不得报告成功加载；缺 dylib 不报成功关联。
    static func validateAssociations(_ rows: [[String: String]]) -> [Violation] {
        rows.compactMap { row in
            if row["is_global"] == "true" && row["category"] == "exact_match" {
                return Violation(rule: "E-07", message: "global 规则不得计入 exact_match")
            }
            if row["evidence"] == "static_filter_match_only" && row["loaded"] != "unknown" {
                return Violation(rule: "E-08", message: "缺少运行时证据的静态关联不得报告成功加载")
            }
            return nil
        }
    }

    // MARK: 报告级聚合

    /// 对既有报告各段跑全部适用规则；不回写报告，只返回违规清单。
    static func validate(report: FKDiagnosticReport) -> [Violation] {
        var violations: [Violation] = []
        violations += validateAccessRecords(report.roots)
        violations += validateAccessRecords(report.filters)
        violations += validateInjectors(report.injectorEvidence)
        violations += validateIntegrity(report.integrity)
        violations += validateAssociations(report.associations)
        return violations
    }
}
