//
//  ProbeTimestamp.swift
//  FilterKit Core — PermissionProbe 时刻工具（Stage 2.4-D2）
//
//  沿用仓库日期字符串惯例：ISO8601/RFC3339 字符串，不使用 `Date` 进入 Models。
//

import Foundation

enum ProbeTimestamp {
    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func current() -> String {
        formatter.string(from: Date())
    }
}
