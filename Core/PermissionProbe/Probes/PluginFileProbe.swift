//
//  PluginFileProbe.swift
//  FilterKit Core — PermissionProbe 插件文件元数据探针（Stage 2.4-D4）
//
//  只做元数据/类型检查（stat），不读取 dylib 内容、不加载/执行 Mach-O；
//  元数据可读 ≠ 内容可读。输入路径来自上游候选配对结果，探针不重复扫描目录。
//  只读：不删除、不替换、不改软链。
//

import Foundation
import Models

/// 插件 dylib 文件元数据探针。
public final class PluginFileProbe: PermissionProbing {

    public let probeID = "plugin.file.metadata"

    private let dylibPaths: [String]
    private let fileAccess: FileAccessChecking

    public init(dylibPaths: [String], fileAccess: FileAccessChecking) {
        self.dylibPaths = dylibPaths
        self.fileAccess = fileAccess
    }

    public func run() -> [ProbeEvidence] {
        let paths = dylibPaths.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !paths.isEmpty else {
            return [Self.notExecutedEvidence()]
        }

        return paths.map { path in
            let url = URL(fileURLWithPath: path)
            let inspect = fileAccess.inspect(url)

            let status: ProbeStatus
            let observed: String

            if !inspect.exists {
                status = ProbeStatusClassifier.classify(
                    exists: false,
                    errorDomain: inspect.errorDomain,
                    errorCode: inspect.errorCode
                )
                observed = "unknown"
            } else if inspect.isDirectory == true {
                status = .failed
                observed = "directory"
            } else {
                status = .passed
                observed = "dylib-metadata"
            }

            return ProbeEvidence(
                probeID: probeID,
                operation: .stat,
                category: .pluginFiles,
                status: status,
                target: url.lastPathComponent,
                observedValue: observed,
                errorDomain: inspect.errorDomain,
                errorCode: inspect.errorCode,
                executedAt: ProbeTimestamp.current()
            )
        }
    }

    private static func notExecutedEvidence() -> ProbeEvidence {
        ProbeEvidence(
            probeID: "plugin.file.metadata",
            operation: .stat,
            category: .pluginFiles,
            status: .notExecuted,
            target: "plugin-dylib",
            observedValue: "no paired dylib path",
            executedAt: ProbeTimestamp.current()
        )
    }
}
