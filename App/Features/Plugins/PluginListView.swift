//
//  PluginListView.swift
//  FilterKit Features — Plugins（Stage 2.3 GUI Foundation）
//
//  列表、搜索、分段筛选与详情跳转；不含启用/禁用、删除或编辑入口。
//

import SwiftUI
import Models
import Core

struct PluginListView: View {
    private let dependencies: AppDependencies
    @State private var viewModel: PluginListViewModel

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        self._viewModel = State(
            initialValue: PluginListViewModel(plugins: dependencies.envelope?.plugins ?? [])
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Filter", selection: $viewModel.segment) {
                        ForEach(PluginListSegment.allCases) { segment in
                            Text(segment.title).tag(segment)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("plugins.segment")
                }

                if viewModel.summaries.isEmpty {
                    ContentUnavailableView(
                        "No Plugins",
                        systemImage: "puzzlepiece",
                        description: Text("当前报告中没有匹配的插件条目。")
                    )
                } else {
                    ForEach(viewModel.summaries) { summary in
                        NavigationLink {
                            if let plugin = viewModel.plugin(id: summary.pluginID) {
                                PluginDetailView(plugin: plugin)
                            }
                        } label: {
                            row(summary)
                        }
                    }
                }
            }
            .accessibilityIdentifier("plugins.list")
            .searchable(text: $viewModel.keyword, prompt: "Search name or ID")
            .navigationTitle("Plugins")
        }
    }

    private func row(_ summary: PluginRowSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(summary.name)
                    .font(.headline)
                    // 列表行标识落在主列 StaticText 上；挂在 NavigationLink 容器
                    // 上不会进入 Cell/StaticText 的 AX identifier（四轮实测 0 匹配）。
                    .accessibilityIdentifier("plugins.row.\(summary.pluginID)")
                Spacer()
                if let version = summary.version {
                    Text(version)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Text(summary.dylibName ?? "Unknown")
                .font(.caption)
                .foregroundColor(.secondary)
            HStack(spacing: 6) {
                StatusBadgeView(status: summary.installed)
                StatusBadgeView(status: summary.configured)
                StatusBadgeView(status: summary.loaded)
                Text(summary.pairing)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.secondary.opacity(0.12))
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    PluginListView(dependencies: AppDependencies(
        reportProvider: StaticReportProvider(envelope: SyntheticReportFactory.previewEnvelope()),
        exporter: ReportExporter()
    ))
}
