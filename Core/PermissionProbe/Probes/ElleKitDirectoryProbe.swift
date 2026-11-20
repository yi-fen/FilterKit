//
//  ElleKitDirectoryProbe.swift
//  FilterKit Core — PermissionProbe ElleKit 目录探针（Stage 2.4-D3）
//
//  复用 Adapter / PathResolver 已解析的 TweakInject 目录作为输入；不在探针内
//  重复路线路径规则，不硬编码三条路线路径，未知 Profile 由上游不提供路径，
//  探针记 notExecuted。证据分：stat（存在/类型/软链）、resolve（软链落点可达）、
//  list（可枚举）。元数据通过 ≠ 枚举通过。
//  只读：不进入目录修改内容、不改软链。
//

import Foundation
import Models

/// ElleKit TweakInject 目录访问探针。
public final class ElleKitDirectoryProbe: PermissionProbing {

    public let probeID = "ellekit.directory.access"

    private let resolvedDirectory: String?
    private let route: String?
    private let fileAccess: FileAccessChecking

    public init(resolvedDirectory: String?,
                route: String? = nil,
                fileAccess: FileAccessChecking) {
        self.resolvedDirectory = resolvedDirectory
        self.route = route
        self.fileAccess = fileAccess
    }

    public func run() -> [ProbeEvidence] {
        guard let path = resolvedDirectory?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else {
            return [Self.notExecutedEvidence(route: route)]
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
            observedType = inspect.isSymlink == true ? "symlink-directory" : "directory"
        }

        let routeLabel = route ?? "unknown-route"
        let statEvidence = ProbeEvidence(
            probeID: probeID,
            operation: .stat,
            category: .ellekit,
            status: statStatus,
            target: "ellekit-tweak-inject",
            observedValue: "\(observedType) · route=\(routeLabel)",
            errorDomain: inspect.errorDomain,
            errorCode: inspect.errorCode,
            executedAt: ProbeTimestamp.current()
        )

        let resolveEvidence: ProbeEvidence
        if inspect.isSymlink == true {
            let resolved = url.standardizedFileURL
            let resolvedInspect = fileAccess.inspect(resolved)
            resolveEvidence = ProbeEvidence(
                probeID: "ellekit.directory.symlink",
                operation: .resolve,
                category: .ellekit,
                status: resolvedInspect.exists ? .passed : .unknown,
                target: "ellekit-tweak-inject",
                observedValue: resolvedInspect.exists ? "symlink-target-reachable" : "symlink-target-unreachable",
                errorDomain: resolvedInspect.errorDomain,
                errorCode: resolvedInspect.errorCode,
                executedAt: ProbeTimestamp.current()
            )
        } else {
            resolveEvidence = ProbeEvidence(
                probeID: "ellekit.directory.symlink",
                operation: .resolve,
                category: .ellekit,
                status: statStatus == .passed ? .passed : .notExecuted,
                target: "ellekit-tweak-inject",
                observedValue: inspect.isSymlink == nil ? "symlink-unknown" : "not-symlink",
                executedAt: ProbeTimestamp.current()
            )
        }

        let listEvidence: ProbeEvidence
        switch statStatus {
        case .passed:
            do {
                let entries = try fileAccess.listDirectory(url)
                listEvidence = ProbeEvidence(
                    probeID: "ellekit.directory.enumerate",
                    operation: .list,
                    category: .ellekit,
                    status: .passed,
                    target: "ellekit-tweak-inject",
                    observedValue: "entries: \(entries.count)",
                    executedAt: ProbeTimestamp.current()
                )
            } catch {
                let ns = error as NSError
                listEvidence = ProbeEvidence(
                    probeID: "ellekit.directory.enumerate",
                    operation: .list,
                    category: .ellekit,
                    status: ProbeStatusClassifier.classify(
                        exists: true,
                        errorDomain: ns.domain,
                        errorCode: ns.code
                    ),
                    target: "ellekit-tweak-inject",
                    observedValue: nil,
                    errorDomain: ns.domain,
                    errorCode: ns.code,
                    executedAt: ProbeTimestamp.current()
                )
            }
        default:
            listEvidence = ProbeEvidence(
                probeID: "ellekit.directory.enumerate",
                operation: .list,
                category: .ellekit,
                status: .notExecuted,
                target: "ellekit-tweak-inject",
                observedValue: "skipped: directory stat not passed",
                executedAt: ProbeTimestamp.current()
            )
        }

        return [statEvidence, resolveEvidence, listEvidence]
    }

    private static func notExecutedEvidence(route: String?) -> ProbeEvidence {
        ProbeEvidence(
            probeID: "ellekit.directory.access",
            operation: .stat,
            category: .ellekit,
            status: .notExecuted,
            target: "ellekit-tweak-inject",
            observedValue: "no resolved tweak-inject path · route=\(route ?? "unknown-route")",
            executedAt: ProbeTimestamp.current()
        )
    }
}
