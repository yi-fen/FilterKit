//
//  PluginDetailView.swift
//  FilterKit 0.1-E3 Plugin Detail & App Association Explorer
//
//  插件详情：三态分行、文件信息、证据、关联分段。数据由 ViewModel/投影
//  注入，本视图不创建 Repository、不触发扫描；Repository 接线留 E4。
//

import SwiftUI
import Core

struct PluginDetailView: View {
    let detail: PluginDetailEntry
    /// 关联行导航路由；默认纯展示，根视图注入插件 → App 方向路由。
    var associationRoute: (PluginAssociationEntry) -> PluginNavigationRoute? = { _ in nil }

    var body: some View {
        List {
            Section("Plugin") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(detail.displayName)
                        .font(.headline)
                    Text(detail.fileName)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            Section("Installation") {
                PluginStatusCard(
                    installed: detail.installed,
                    configured: detail.configured,
                    loaded: detail.loaded
                )
            }

            PluginFileInformationSection(detail: detail)
            PluginEvidenceSection(detail: detail)

            Section("App Associations") {
                LabeledContent("Exact Matches", value: "\(detail.exactMatchCount)")
                PluginAssociationSection(associations: detail.associations, route: associationRoute)
            }
        }
        .navigationTitle("Plugin Details")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("detail.plugin.\(detail.id)")
    }
}
