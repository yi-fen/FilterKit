//
//  PermissionProbeService.swift
//  FilterKit Core — PermissionProbe 统一编排服务（Stage 2.4-D7）
//
//  装配探针数组并逐条执行；单项探针抛错不中断其他探针，失败证据保留原探针
//  身份（probeID 不变）。服务只做只读编排，不触发扫描/写入/装卸。
//

import Foundation
import Models

/// 统一探针编排服务。
public final class PermissionProbeService: PermissionProbeServiceProtocol {

    private let probes: [PermissionProbing]
    private let builder: PermissionProbeReportBuilder

    public init(probes: [PermissionProbing],
                builder: PermissionProbeReportBuilder = PermissionProbeReportBuilder()) {
        self.probes = probes
        self.builder = builder
    }

    public func runProbes() -> PermissionProbeReport {
        var evidence: [ProbeEvidence] = []

        for probe in probes {
            let probeEvidence: [ProbeEvidence]
            do {
                probeEvidence = try probe.run()
            } catch {
                probeEvidence = [Self.failureEvidence(probe: probe, error: error)]
            }
            evidence.append(contentsOf: probeEvidence)
        }

        return builder.build(evidence: evidence)
    }

    private static func failureEvidence(probe: PermissionProbing, error: Error) -> ProbeEvidence {
        let ns = error as NSError
        return ProbeEvidence(
            probeID: probe.probeID,
            operation: .inspect,
            category: nil,
            status: .failed,
            target: "probe",
            observedValue: "probe threw during execution",
            errorDomain: ns.domain,
            errorCode: ns.code,
            executedAt: ProbeTimestamp.current()
        )
    }
}
