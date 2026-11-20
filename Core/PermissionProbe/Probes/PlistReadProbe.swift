//
//  PlistReadProbe.swift
//  FilterKit Core — PermissionProbe plist 读取探针（Stage 2.4-D4）
//
//  复用既有 `PlistDataReading`（Stage 1 Reader），不重写 plist 解析器。本探针只
//  回答「指定路径能否读取为 Data」；内容是否合法由既有 Parser 五态裁决，探针
//  不把读取成功记为 plist 配置成功。读取失败保留 Reader 状态与错误码。
//  只读：不修改 plist 内容。
//

import Foundation
import Models

/// 插件 plist 读取探针。
public final class PlistReadProbe: PermissionProbing {

    public let probeID = "plugin.plist.read"

    private let plistPaths: [String]
    private let reader: PlistDataReading

    public init(plistPaths: [String], reader: PlistDataReading) {
        self.plistPaths = plistPaths
        self.reader = reader
    }

    public func run() -> [ProbeEvidence] {
        let paths = plistPaths.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !paths.isEmpty else {
            return [Self.notExecutedEvidence()]
        }

        return paths.map { path in
            let result = reader.read(path: path)
            let status: ProbeStatus
            let observed: String?

            switch result.status {
            case .success:
                status = .passed
                observed = "data-readable: \(result.data?.count ?? 0) bytes"
            case .notFound:
                status = .unavailable
                observed = nil
            case .accessDenied:
                status = .permissionDenied
                observed = nil
            case .readFailed:
                status = .failed
                observed = nil
            }

            return ProbeEvidence(
                probeID: probeID,
                operation: .read,
                category: .pluginFiles,
                status: status,
                target: URL(fileURLWithPath: path).lastPathComponent,
                observedValue: observed,
                errorDomain: nil,
                errorCode: result.errorCode,
                executedAt: ProbeTimestamp.current()
            )
        }
    }

    private static func notExecutedEvidence() -> ProbeEvidence {
        ProbeEvidence(
            probeID: "plugin.plist.read",
            operation: .read,
            category: .pluginFiles,
            status: .notExecuted,
            target: "plugin-plist",
            observedValue: "no paired plist path",
            executedAt: ProbeTimestamp.current()
        )
    }
}
