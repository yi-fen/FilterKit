//
//  CombinedReportEncoder.swift
//  FilterKit Core — R3-C Live Diagnostics Export Bridge
//
//  单文件兼容导出：既有信封字段保持顶层原样，新增 `diagnostics` 扩展段。
//  只做序列化归并：不重新扫描、不补全字段、不覆盖信封既有键；诊断段为 nil
//  时按 neverRun 空段导出，不生成合成插件数据。
//

import Foundation
import Models

/// 信封 + 诊断段合并编码器（路线 A）。
public struct CombinedReportEncoder {
    public init() {}

    /// 编码单文件 JSON。`diagnostics` 为 nil 时写入 neverRun 空段。
    public func encode(envelope: ReportEnvelope,
                       diagnostics: DiagnosticsExportSection?) throws -> Data {
        let envelopeData = try ReportExporter().export(envelope)
        guard var root = try JSONSerialization.jsonObject(with: envelopeData) as? [String: Any] else {
            throw ReportExportError.encodingFailed("Envelope root is not a JSON object")
        }

        let section = diagnostics ?? DiagnosticsExportSection.neverRun()
        let sectionEncoder = JSONEncoder()
        sectionEncoder.outputFormatting = [.sortedKeys]
        sectionEncoder.dateEncodingStrategy = .iso8601
        let sectionData = try sectionEncoder.encode(section)
        guard let sectionObject = try JSONSerialization.jsonObject(with: sectionData) as? [String: Any] else {
            throw ReportExportError.encodingFailed("Diagnostics segment root is not a JSON object")
        }

        // 诊断段是新增扩展键；不回写、不删除信封既有键。
        root["diagnostics"] = sectionObject

        do {
            return try JSONSerialization.data(
                withJSONObject: root,
                options: [.prettyPrinted, .sortedKeys]
            )
        } catch {
            throw ReportExportError.encodingFailed("\(error)")
        }
    }
}
