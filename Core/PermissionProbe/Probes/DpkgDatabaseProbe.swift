//
//  DpkgDatabaseProbe.swift
//  FilterKit Core — PermissionProbe 包数据库探针（Stage 2.4-D4）
//
//  仅做元数据与内容可读性检查（只读 status 文件）；不执行 `dpkg -i/-r`、
//  `apt` 或任何包装卸命令，不写入 dpkg 数据库。路径由上游装配注入，探针不在
//  内部硬编码 /var/lib/dpkg 或做回退猜测。
//

import Foundation
import Models

/// dpkg 状态文件只读探针。
public final class DpkgDatabaseProbe: PermissionProbing {

    public let probeID = "package.database.read"

    private let statusFilePath: String?
    private let fileAccess: FileAccessChecking

    public init(statusFilePath: String?, fileAccess: FileAccessChecking) {
        self.statusFilePath = statusFilePath
        self.fileAccess = fileAccess
    }

    public func run() -> [ProbeEvidence] {
        guard let path = statusFilePath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else {
            return [Self.notExecutedEvidence()]
        }

        let url = URL(fileURLWithPath: path)
        let inspect = fileAccess.inspect(url)

        let statStatus: ProbeStatus
        if !inspect.exists {
            statStatus = ProbeStatusClassifier.classify(
                exists: false,
                errorDomain: inspect.errorDomain,
                errorCode: inspect.errorCode
            )
        } else if inspect.isDirectory == true {
            statStatus = .failed
        } else {
            statStatus = .passed
        }

        let statEvidence = ProbeEvidence(
            probeID: "package.database.metadata",
            operation: .stat,
            category: .packageDatabase,
            status: statStatus,
            target: "dpkg-status",
            observedValue: inspect.isDirectory == true ? "directory" : "file",
            errorDomain: inspect.errorDomain,
            errorCode: inspect.errorCode,
            executedAt: ProbeTimestamp.current()
        )

        let readEvidence: ProbeEvidence
        switch statStatus {
        case .passed:
            do {
                let data = try fileAccess.read(url)
                readEvidence = ProbeEvidence(
                    probeID: probeID,
                    operation: .read,
                    category: .packageDatabase,
                    status: data.isEmpty ? .failed : .passed,
                    target: "dpkg-status",
                    observedValue: data.isEmpty ? "empty" : "readable: \(data.count) bytes",
                    executedAt: ProbeTimestamp.current()
                )
            } catch {
                let ns = error as NSError
                readEvidence = ProbeEvidence(
                    probeID: probeID,
                    operation: .read,
                    category: .packageDatabase,
                    status: ProbeStatusClassifier.classify(
                        exists: true,
                        errorDomain: ns.domain,
                        errorCode: ns.code
                    ),
                    target: "dpkg-status",
                    observedValue: nil,
                    errorDomain: ns.domain,
                    errorCode: ns.code,
                    executedAt: ProbeTimestamp.current()
                )
            }
        default:
            readEvidence = ProbeEvidence(
                probeID: probeID,
                operation: .read,
                category: .packageDatabase,
                status: .notExecuted,
                target: "dpkg-status",
                observedValue: "skipped: metadata stat not passed",
                executedAt: ProbeTimestamp.current()
            )
        }

        return [statEvidence, readEvidence]
    }

    private static func notExecutedEvidence() -> ProbeEvidence {
        ProbeEvidence(
            probeID: "package.database.read",
            operation: .read,
            category: .packageDatabase,
            status: .notExecuted,
            target: "dpkg-status",
            observedValue: "no dpkg status path supplied",
            executedAt: ProbeTimestamp.current()
        )
    }
}
