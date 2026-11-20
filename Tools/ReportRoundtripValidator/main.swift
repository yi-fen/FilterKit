//
//  main.swift
//  ReportRoundtripValidator — C-F5 P2 G9 往返解析校验（D1）
//
//  读取模拟器导出的 JSON 样本，解码为 ReportEnvelope，与
//  SyntheticReportFactory.previewEnvelope() 合成基线比对（忽略 generatedAt）；
//  输出机器可读结果 JSON。只做解码与结构等义比对：不扫描、不访问文件系统
//  （除输入/输出路径外）、不修改原始信封。
//
//  用法：
//    swift run ReportRoundtripValidator --input <export.json> --output <roundtrip-result.json>
//
//  退出码：0 解码成功且等义；1 解码失败或不等义；2 参数缺失。
//

import Foundation
import Models
import AppPresentation

struct Counts: Codable, Equatable {
    let plugins: Int
    let unknownItems: Int
    let warnings: Int
}

/// 可选字符串比较：相等返回 `nil` 以落到下一排序键；`nil` 排前。
/// 与 `Core/ReportExporter/ReportSerialization.swift` 的 `compare` 同口径。
private func compare(_ lhs: String?, _ rhs: String?) -> Bool? {
    switch (lhs, rhs) {
    case (nil, nil): return nil
    case (nil, _): return true
    case (_, nil): return false
    case let (a?, b?): return a == b ? nil : a < b
    }
}

/// 等义比对前的数组归一化。导出侧按 `ReportSerialization` 策略做确定性
/// 排序，而工厂基线保持构造顺序；往返等义与导出顺序无关，故两侧先按同一
/// 排序键归一化，再做整体 Equatable 判等。
private func normalized(_ envelope: ReportEnvelope) -> ReportEnvelope {
    var e = envelope
    e.plugins = e.plugins.sorted { lhs, rhs in
        compare(lhs.pluginID, rhs.pluginID)
            ?? compare(lhs.name, rhs.name)
            ?? compare(lhs.plistPath ?? lhs.dylibPath, rhs.plistPath ?? rhs.dylibPath)
            ?? false
    }
    e.unknownItems = e.unknownItems.sorted { lhs, rhs in
        compare(lhs.path ?? lhs.base, rhs.path ?? rhs.base)
            ?? compare(lhs.reason, rhs.reason)
            ?? compare(lhs.sourceStage, rhs.sourceStage)
            ?? false
    }
    e.warnings = e.warnings.sorted { lhs, rhs in
        compare(lhs.code, rhs.code)
            ?? compare(lhs.sourceStage, rhs.sourceStage)
            ?? compare(lhs.message, rhs.message)
            ?? false
    }
    return e
}

struct RoundtripResult: Codable, Equatable {
    let decodable: Bool
    let inputFile: String
    let baselineGeneratorVersion: String
    let counts: Counts
    let equalIgnoringGeneratedAt: Bool
    let messages: [String]
}

func argumentValue(_ name: String) -> String? {
    let args = CommandLine.arguments
    guard let index = args.firstIndex(of: name), index + 1 < args.count else {
        return nil
    }
    return args[index + 1]
}

let inputPath = argumentValue("--input")
let outputPath = argumentValue("--output")

guard let inputPath, let outputPath else {
    fputs("usage: ReportRoundtripValidator --input <json> --output <result.json>\n", stderr)
    exit(2)
}

let inputURL = URL(fileURLWithPath: inputPath)
let outputURL = URL(fileURLWithPath: outputPath)

let baseline = SyntheticReportFactory.previewEnvelope()
var messages: [String] = []
var decodable = false
var equalIgnoringGeneratedAt = false
var counts = Counts(plugins: 0, unknownItems: 0, warnings: 0)

do {
    let data = try Data(contentsOf: inputURL)
    let decoded = try JSONDecoder().decode(ReportEnvelope.self, from: data)
    decodable = true

    counts = Counts(
        plugins: decoded.plugins.count,
        unknownItems: decoded.unknownItems.count,
        warnings: decoded.warnings.count
    )

    var baselineCompared = baseline
    baselineCompared.generatedAt = nil
    var decodedCompared = decoded
    decodedCompared.generatedAt = nil
    equalIgnoringGeneratedAt = normalized(decodedCompared) == normalized(baselineCompared)

    if counts.plugins != baseline.plugins.count {
        messages.append("plugins 计数 \(counts.plugins) != 基线 \(baseline.plugins.count)")
    }
    if counts.unknownItems != baseline.unknownItems.count {
        messages.append("unknownItems 计数 \(counts.unknownItems) != 基线 \(baseline.unknownItems.count)")
    }
    if counts.warnings != baseline.warnings.count {
        messages.append("warnings 计数 \(counts.warnings) != 基线 \(baseline.warnings.count)")
    }
    if !equalIgnoringGeneratedAt {
        messages.append("解码信封与合成基线（忽略 generatedAt）不等义")
    }
} catch {
    messages.append("解码失败：\(error.localizedDescription)")
}

let result = RoundtripResult(
    decodable: decodable,
    inputFile: inputPath,
    baselineGeneratorVersion: baseline.generatorVersion,
    counts: counts,
    equalIgnoringGeneratedAt: equalIgnoringGeneratedAt,
    messages: messages
)

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
try encoder.encode(result).write(to: outputURL)

if !decodable || !equalIgnoringGeneratedAt {
    exit(1)
}
