//
//  SandboxAccessProbe.swift
//  FilterKit Core — PermissionProbe 沙盒访问探针（Stage 2.4-D5）
//
//  按实际资源访问逐项取证：每个目标独立记录可达/拒绝/不存在，不笼统判定
//  沙盒「已关闭」。访问失败不中断其他目标。本探针只做只读 inspect，不触发
//  写入、不申请额外权限。
//

import Foundation
import Models

/// 沙盒访问目标（标签 + 路径；标签用于界面展示，路径不回显到诊断摘要）。
public struct SandboxTarget: Equatable {
    public var label: String
    public var path: String

    public init(label: String, path: String) {
        self.label = label
        self.path = path
    }
}

/// 沙盒资源访问探针。
public final class SandboxAccessProbe: PermissionProbing {

    public let probeID = "sandbox.resource.access"

    private let targets: [SandboxTarget]
    private let fileAccess: FileAccessChecking

    public init(targets: [SandboxTarget], fileAccess: FileAccessChecking) {
        self.targets = targets
        self.fileAccess = fileAccess
    }

    public func run() -> [ProbeEvidence] {
        guard !targets.isEmpty else {
            return [
                ProbeEvidence(
                    probeID: probeID,
                    operation: .inspect,
                    category: .sandbox,
                    status: .notExecuted,
                    target: "sandbox-target",
                    observedValue: "[resourceAccess] no sandbox access target supplied",
                    executedAt: ProbeTimestamp.current()
                )
            ]
        }

        return targets.map { target in
            let url = URL(fileURLWithPath: target.path)
            let inspect = fileAccess.inspect(url)

            let status: ProbeStatus
            let observed: String

            if !inspect.exists {
                status = ProbeStatusClassifier.classify(
                    exists: false,
                    errorDomain: inspect.errorDomain,
                    errorCode: inspect.errorCode
                )
                observed = "[resourceAccess] unreachable"
            } else {
                status = .passed
                observed = "[resourceAccess] reachable"
            }

            return ProbeEvidence(
                probeID: probeID,
                operation: .inspect,
                category: .sandbox,
                status: status,
                target: target.label,
                observedValue: observed,
                errorDomain: inspect.errorDomain,
                errorCode: inspect.errorCode,
                executedAt: ProbeTimestamp.current()
            )
        }
    }
}
