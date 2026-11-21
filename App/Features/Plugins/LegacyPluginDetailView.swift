//
//  LegacyPluginDetailView.swift
//  FilterKit Features — Plugin Detail（Stage 2.3 GUI Foundation，信封版 Legacy）
//
//  状态 / 文件 / 配对 / Filter 规则 / 归属 / 证据分区，全部由 `PluginDetailModel`
//  只读派生。详情页只读，无编辑、删除、修复或启停入口。
//

import SwiftUI
import Models

// 0.1-E4：信封版旧详情视图改名 Legacy，避免与 E3 `PluginDetailView(detail:)`
// 同模块重名；文件保留不删，不再被 Plugins Tab 引用，导出 / 信封链路零改动。
struct LegacyPluginDetailView: View {
    private let plugin: Plugin
    private let model: PluginDetailModel

    init(plugin: Plugin) {
        self.plugin = plugin
        self.model = PluginDetailModel(plugin: plugin)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text(model.pluginID)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .accessibilityIdentifier("detail.plugin-id")
                section("Plugin Status", "detail.section.status", model.statusRows)
                section("Files", "detail.section.files", model.fileRows)
                section("Pairing", "detail.section.pairing", model.pairingRows)
                section("Filter Rules", "detail.section.filter", model.filterRows)
                section("Ownership", "detail.section.ownership", model.ownershipRows)
                section("Evidence", "detail.section.evidence", model.evidenceRows)
            }
            .padding()
        }
        .navigationTitle(model.name)
    }

    private func section(_ title: String, _ identifier: String, _ rows: [DetailRow]) -> some View {
        SectionCardView(title: title, identifier: identifier) {
            if rows.isEmpty {
                Text("—")
                    .foregroundColor(.secondary)
            } else {
                ForEach(rows) { row in
                    InfoRowView(label: row.label, value: row.value, status: row.status)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        LegacyPluginDetailView(plugin: SyntheticReportFactory.previewEnvelope().plugins[0])
    }
}
