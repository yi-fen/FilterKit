//
//  EntitlementProbe.swift
//  FilterKit Core — PermissionProbe entitlement 探针（Stage 2.4-D5 / R2-A）
//
//  三类证据分开：代码签名（signed）entitlement、进程运行时（runtime）entitlement、
//  实际资源访问（resourceAccess，由 D2/D3/D4 目录与文件探针及 SandboxAccessProbe
//  独立取证，不在本探针内合并）。本探针只记录 entitlement 检查结果；检查通过仅代表
//  接口读取成功，不代表权限已放行，不把存在某 entitlement 键记为 passed 权限。
//
//  冻结 Models 未改动：来源标签写入 `observedValue` 前缀，ProbeEvidence 字段不变。
//

import Foundation
import Models

/// entitlement 检查探针（进程 runtime + 代码签名 signed 两条证据）。
public final class EntitlementProbe: PermissionProbing {

    public let probeID = "entitlement.inspect"

    private let processInspector: EntitlementInspecting
    private let codeSignInspector: CodeSignInspecting

    public init(processInspector: EntitlementInspecting,
                codeSignInspector: CodeSignInspecting) {
        self.processInspector = processInspector
        self.codeSignInspector = codeSignInspector
    }

    public func run() -> [ProbeEvidence] {
        [
            Self.evidence(
                snapshot: processInspector.inspectProcessEntitlements(),
                source: .runtime,
                probeID: "entitlement.process",
                target: "process-entitlement"
            ),
            Self.evidence(
                snapshot: codeSignInspector.inspectCodeSignEntitlements(),
                source: .signed,
                probeID: "entitlement.code-sign",
                target: "code-sign-entitlement"
            )
        ]
    }

    private static func evidence(snapshot: EntitlementSnapshot,
                                 source: EntitlementEvidenceSource,
                                 probeID: String,
                                 target: String) -> ProbeEvidence {
        let label = source.rawValue
        if snapshot.available {
            return ProbeEvidence(
                probeID: probeID,
                operation: .inspect,
                category: .entitlement,
                status: .passed,
                target: target,
                observedValue: "[\(label)] entitlement keys: \(snapshot.observedKeys.count)",
                executedAt: ProbeTimestamp.current()
            )
        }
        return ProbeEvidence(
            probeID: probeID,
            operation: .inspect,
            category: .entitlement,
            status: .unavailable,
            target: target,
            observedValue: "[\(label)] \(snapshot.reason ?? "inspection unavailable")",
            executedAt: ProbeTimestamp.current()
        )
    }
}
