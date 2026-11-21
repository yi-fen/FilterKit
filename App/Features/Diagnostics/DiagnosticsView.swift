//
//  DiagnosticsView.swift
//  FilterKit Features — Diagnostics（Stage 2.3 GUI Foundation）
//
//  环境 / JBROOT / Dynamic Libraries / 枚举 / 解析 / Warnings / Unknown Items
//  分组只读展示；不触发重新扫描，不回写设备。
//

import SwiftUI
import Models
import Core

struct DiagnosticsView: View {
    private let dependencies: AppDependencies
    @State private var viewModel: DiagnosticsViewModel

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        self._viewModel = State(
            initialValue: DiagnosticsViewModel(
                provider: dependencies.reportProvider,
                probeReport: dependencies.probeReport,
                diagnosticsStore: dependencies.diagnosticsStore
            )
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Button {
                        viewModel.runReadOnlyDiagnostics()
                    } label: {
                        HStack {
                            if viewModel.isScanning { ProgressView().padding(.trailing, 6) }
                            Text(viewModel.isScanning ? "Scanning read-only diagnostics…" : "Run 0.1.18 Read-only Diagnostics")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isScanning)
                    .accessibilityIdentifier("diagnostics.runReadOnly")

                    ForEach(viewModel.sections) { section in
                        SectionCardView(title: section.title, identifier: "diagnostics.section.\(section.id)") {
                            if section.isEmpty {
                                Text("—")
                                    .foregroundColor(.secondary)
                            } else {
                                ForEach(section.rows) { row in
                                    InfoRowView(label: row.label, value: row.value, status: row.status)
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Diagnostics")
        }
    }
}

#Preview {
    DiagnosticsView(dependencies: AppDependencies(
        reportProvider: StaticReportProvider(envelope: SyntheticReportFactory.previewEnvelope()),
        exporter: ReportExporter()
    ))
}
