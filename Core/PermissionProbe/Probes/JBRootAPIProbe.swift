//
//  JBRootAPIProbe.swift
//  FilterKit Core — PermissionProbe jbroot() API 探针（Stage 2.4-D6 / R2-B）
//
//  四层证据分开记录：符号可用 / 调用成功 / 返回路径有效 / 与已确认 JBROOT 一致。
//  一致性比较走 `JBRootPathComparator` 分层取证（raw / normalized / symlink /
//  accessible），不再使用原始字符串 `==`。API 一致 ≠ 内容可访问；内容可达性由
//  D2 目录探针独立取证。API 未核实前由占位 resolver 返回不可用，证据保留
//  unavailable/unknown，不伪造调用结果。
//

import Foundation
import Models

/// jbroot() API 探针。
public final class JBRootAPIProbe: PermissionProbing {

    public let probeID = "jbroot-api.inspect"

    private let resolver: JBRootResolving
    private let confirmedJBRoot: String?
    private let fileAccess: FileAccessChecking?

    public init(resolver: JBRootResolving,
                confirmedJBRoot: String?,
                fileAccess: FileAccessChecking? = nil) {
        self.resolver = resolver
        self.confirmedJBRoot = confirmedJBRoot
        self.fileAccess = fileAccess
    }

    public func run() -> [ProbeEvidence] {
        let snapshot = resolver.resolveJBRootViaAPI()

        let symbolEvidence = ProbeEvidence(
            probeID: "jbroot-api.symbol",
            operation: .inspect,
            category: .jbrootAPI,
            status: snapshot.symbolAvailable ? .passed : .unavailable,
            target: "jbroot-symbol",
            observedValue: snapshot.symbolAvailable ? "symbol-available" : snapshot.errorReason,
            executedAt: ProbeTimestamp.current()
        )

        let invokeEvidence = ProbeEvidence(
            probeID: "jbroot-api.invoke",
            operation: .invoke,
            category: .jbrootAPI,
            status: snapshot.invoked ? .passed : .unavailable,
            target: "jbroot-invoke",
            observedValue: snapshot.invoked ? "invoked" : snapshot.errorReason,
            executedAt: ProbeTimestamp.current()
        )

        let pathEvidence: ProbeEvidence
        if let resolved = snapshot.resolvedPath, !resolved.isEmpty {
            pathEvidence = ProbeEvidence(
                probeID: "jbroot-api.path",
                operation: .resolve,
                category: .jbrootAPI,
                status: .passed,
                target: "jbroot-returned-path",
                observedValue: "path-resolved",
                executedAt: ProbeTimestamp.current()
            )
        } else {
            pathEvidence = ProbeEvidence(
                probeID: "jbroot-api.path",
                operation: .resolve,
                category: .jbrootAPI,
                status: .unknown,
                target: "jbroot-returned-path",
                observedValue: "no resolved path",
                executedAt: ProbeTimestamp.current()
            )
        }

        let comparison = JBRootPathComparator.compare(
            returned: snapshot.resolvedPath,
            confirmed: confirmedJBRoot,
            fileAccess: fileAccess
        )
        let verdict = JBRootPathComparator.verdict(comparison)
        let consistencyStatus: ProbeStatus
        switch verdict {
        case .passed: consistencyStatus = .passed
        case .failed: consistencyStatus = .failed
        case .unknown: consistencyStatus = .unknown
        }

        let consistencyEvidence = ProbeEvidence(
            probeID: "jbroot-api.consistency",
            operation: .resolve,
            category: .jbrootAPI,
            status: consistencyStatus,
            target: "jbroot-consistency",
            observedValue: JBRootPathComparator.summary(comparison),
            executedAt: ProbeTimestamp.current()
        )

        return [symbolEvidence, invokeEvidence, pathEvidence, consistencyEvidence]
    }
}
