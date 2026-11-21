//
// DiagnosticsViewModel.swift
// FilterKit Features — Diagnostics
//

import SwiftUI
import Models
import Core

@Observable
final class DiagnosticsViewModel {
    private let provider: ReportProviding
    private let probeReport: PermissionProbeReport?
    private let diagnosticsStore: DiagnosticsReportStore
    private(set) var sections: [DiagnosticsSection]
    private(set) var isScanning = false

    init(provider: ReportProviding,
         probeReport: PermissionProbeReport? = nil,
         diagnosticsStore: DiagnosticsReportStore = DiagnosticsReportStore()) {
        self.provider = provider
        self.probeReport = probeReport
        self.diagnosticsStore = diagnosticsStore
        let envelopeSections = DiagnosticsMapper.sections(provider.envelope)
        let probeSections = ProbeDiagnosticsMapper.sections(probeReport)
        self.sections = envelopeSections + probeSections
    }

    /// Runs only after explicit user action. The scanner never mutates jailbreak files.
    func runReadOnlyDiagnostics() {
        guard !isScanning else { return }
        isScanning = true
        diagnosticsStore.beginScan()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // 引擎当前为非抛出接口；内部失败按冻结语义记入 findings / 未知状态。
            // 扫描完成即写入共享 Store；空结果记 completed（空条目），与失败态区分。
            let report = ReadOnlyDiagnosticsEngine().scan()
            let section = DiagnosticsReportMapper.section(from: report)
            let rows: [DiagnosticsSection] = [
                DiagnosticsSection(id: "legacy-summary", title: "0.1.18 Diagnostic Summary", rows: [
                    DetailRow(label: "JBROOT candidates", value: "\(report.roots.count)"),
                    DetailRow(label: "DynamicLibraries directories", value: "\(report.dynamicLibraryDirectories.count)"),
                    DetailRow(label: "dylib files", value: "\(report.plugins.count)"),
                    DetailRow(label: "Filter plists", value: "\(report.filters.count)"),
                    DetailRow(label: "Injector evidence", value: "\(report.injectorEvidence.count)"),
                    DetailRow(label: "DPKG packages", value: "\(report.packages.count)"),
                    DetailRow(label: "File ownership records", value: "\(report.fileOwnership.count)"),
                    DetailRow(label: "Integrity records", value: "\(report.integrity.count)"),
                    DetailRow(label: "Helper candidates", value: "\(report.helperCandidates.count)"),
                    DetailRow(label: "Helper registrations", value: "\(report.helperRegistrations.count)"),
                    DetailRow(label: "Installed Apps", value: "\(report.applications.count)"),
                    DetailRow(label: "Static App associations", value: "\(report.associations.count)"),
                    DetailRow(label: "Runtime loaded state", value: "Unknown — no independent evidence")
                ]),
                DiagnosticsSection(id: "legacy-roots", title: "JBROOT Candidates", rows: report.roots.map {
                    DetailRow(label: $0["path"] ?? "Unknown", value: "status=\($0["status"] ?? "unknown") · readable=\($0["readable"] ?? "unknown") · structure=\($0["structure_match"] ?? "unknown")")
                }),
                DiagnosticsSection(id: "legacy-dylibs", title: "Discovered Plugins", rows: report.plugins.map {
                    DetailRow(label: $0["name"] ?? "Unknown", value: "\($0["path"] ?? "") · source=\($0["source"] ?? "unknown") · loaded=unknown")
                }),
                DiagnosticsSection(id: "legacy-filters", title: "Filter Rules", rows: report.filters.map {
                    DetailRow(label: $0["plugin"] ?? "Unknown", value: "Bundles: \($0["bundles"] ?? "—") · Executables: \($0["executables"] ?? "—") · Classes: \($0["classes"] ?? "—") · parse=\($0["parse_status"] ?? "unknown")")
                }),
                DiagnosticsSection(id: "legacy-injectors", title: "Injector Evidence", rows: report.injectorEvidence.map {
                    DetailRow(label: $0["type"] ?? "Unknown", value: "package=\($0["package_id"] ?? "—") · image=\($0["image_path"] ?? "—") · scope=\($0["scope"] ?? "static")")
                }),
                DiagnosticsSection(id: "legacy-dpkg", title: "DPKG Packages", rows: report.packages.map {
                    DetailRow(label: $0["package_id"] ?? "Unknown", value: "\($0["version"] ?? "") · \($0["status"] ?? "") · missing=\($0["missing_files"] ?? "0")")
                }),
                DiagnosticsSection(id: "legacy-integrity", title: "File Integrity", rows: report.integrity.map {
                    DetailRow(label: $0["path"] ?? "Unknown", value: "\($0["status"] ?? "unknown") · \($0["disposition"] ?? $0["reason"] ?? "")")
                }),
                DiagnosticsSection(id: "legacy-helpers", title: "RootHelper Read-only Preflight", rows: report.helperCandidates.map {
                    DetailRow(label: $0["path"] ?? "Unknown", value: "executable=\($0["executable"] ?? "unknown") · operation=not_launched")
                } + report.helperRegistrations.map {
                    DetailRow(label: $0["label"] ?? "LaunchDaemon", value: "\($0["program"] ?? "") · exists=\($0["program_exists"] ?? "unknown")")
                }),
                DiagnosticsSection(id: "legacy-apps", title: "Installed Applications", rows: report.applications.map {
                    DetailRow(label: $0["name"] ?? "Unknown", value: "\($0["bundle_id"] ?? "") · \($0["version"] ?? "unknown")")
                }),
                DiagnosticsSection(id: "legacy-associations", title: "Static Plugin ↔ App Matches", rows: report.associations.map {
                    DetailRow(label: "\($0["plugin"] ?? "Unknown") → \($0["bundle_id"] ?? "Unknown")", value: "\($0["match_type"] ?? "match") · static filter only; loaded=unknown")
                }),
                DiagnosticsSection(id: "legacy-findings", title: "Diagnostic Findings", rows: report.findings.map {
                    DetailRow(label: "\($0.title) · \($0.state)", value: $0.detail)
                })
            ]
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.diagnosticsStore.complete(section)
                self.sections = DiagnosticsMapper.sections(self.provider.envelope)
                    + ProbeDiagnosticsMapper.sections(self.probeReport) + rows
                self.isScanning = false
            }
        }
    }
}
