//
//  DiagnosticEvidenceLevel.swift
//  FilterKit Stage 2.6 R3-A7 — 内部证据等级（D-R2-04）
//
//  引擎内部可见；不加入公共 Models，不映射为简单 Pass/Fail。
//  等级与既有 `loaded`/`installed`/`configured` 语义并存：
//  installed=confirmed、configured=confirmed、loaded=unknown 是合法组合。
//

import Foundation

enum DiagnosticEvidenceLevel: String, Codable, Equatable {
    /// 有直接、可核实的证据（运行时镜像 / 精确 dpkg 记录 / 已完成校验）。
    case confirmed
    /// 由静态文件、路径或清单推断，无运行时确认。
    case inferred
    /// 存在线索，但尚未完成校验。
    case unverified
    /// 证据不足，保持未知；不得自动翻成 false/failed/passed。
    case unknown
}
