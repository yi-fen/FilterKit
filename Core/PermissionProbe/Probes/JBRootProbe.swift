//
//  JBRootProbe.swift
//  FilterKit Core — PermissionProbe JBROOT 访问探针（Stage 2.4-D2）
//
//  复用 Stage 1 已确认的 JBROOT 路径作为输入；本探针不做候选收集、不重复实现
//  JBROOT 定位、不回退猜测路径。证据分两条：stat（存在性/类型）与 list（可枚举），
//  元数据检查通过不等于目录可枚举。路径未确认时整组探针记 notExecuted。
//  只读：不进入目录修改任何内容。
//

import Foundation
import Models

/// JBROOT 目录访问探针。
public final class JBRootProbe: PermissionProbing {

    public let probeID = "jbroot.directory.access"

    private let confirmedJBRoot: String?
    private let fileAccess: FileAccessChecking

    public init(confirmedJBRoot: String?, fileAccess: FileAccessChecking) {
        self.confirmedJBRoot = confirmedJBRoot
        self.fileAccess = fileAccess
    }

    public func run() -> [ProbeEvidence] {
        guard let path = confirmedJBRoot?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else {
            return [Self.notExecutedEvidence()]
        }

        let url = URL(fileURLWithPath: path)
        let inspect = fileAccess.inspect(url)

        let statStatus: ProbeStatus
        let observedType: String

        if !inspect.exists {
            statStatus = ProbeStatusClassifier.classify(
                exists: false,
                errorDomain: inspect.errorDomain,
                errorCode: inspect.errorCode
            )
            observedType = "unknown"
        } else if inspect.isDirectory == false {
            statStatus = .failed
            observedType = "file"
        } else {
            statStatus = .passed
            observedType = "directory"
        }

        let statEvidence = ProbeEvidence(
            probeID: probeID,
            operation: .stat,
            category: .jbroot,
            status: statStatus,
            target: "confirmed-jbroot",
            observedValue: observedType,
            errorDomain: inspect.errorDomain,
            errorCode: inspect.errorCode,
            executedAt: ProbeTimestamp.current()
        )

        let listEvidence: ProbeEvidence
        switch statStatus {
        case .passed:
            do {
                let entries = try fileAccess.listDirectory(url)
                listEvidence = ProbeEvidence(
                    probeID: "jbroot.directory.enumerate",
                    operation: .list,
                    category: .jbroot,
                    status: .passed,
                    target: "confirmed-jbroot",
                    observedValue: "entries: \(entries.count)",
                    executedAt: ProbeTimestamp.current()
                )
            } catch {
                let ns = error as NSError
                listEvidence = ProbeEvidence(
                    probeID: "jbroot.directory.enumerate",
                    operation: .list,
                    category: .jbroot,
                    status: ProbeStatusClassifier.classify(
                        exists: true,
                        errorDomain: ns.domain,
                        errorCode: ns.code
                    ),
                    target: "confirmed-jbroot",
                    observedValue: nil,
                    errorDomain: ns.domain,
                    errorCode: ns.code,
                    executedAt: ProbeTimestamp.current()
                )
            }
        default:
            listEvidence = ProbeEvidence(
                probeID: "jbroot.directory.enumerate",
                operation: .list,
                category: .jbroot,
                status: .notExecuted,
                target: "confirmed-jbroot",
                observedValue: "skipped: jbroot stat not passed",
                executedAt: ProbeTimestamp.current()
            )
        }

        return [statEvidence, listEvidence]
    }

    private static func notExecutedEvidence() -> ProbeEvidence {
        ProbeEvidence(
            probeID: "jbroot.directory.access",
            operation: .stat,
            category: .jbroot,
            status: .notExecuted,
            target: "confirmed-jbroot",
            observedValue: "no confirmed jbroot path",
            executedAt: ProbeTimestamp.current()
        )
    }
}
