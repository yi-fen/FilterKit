//
//  ApplicationDetailView.swift
//  FilterKit 0.1-E3 Plugin Detail & App Association Explorer
//
//  App 详情：基础信息 + 插件关联分段。关联为静态匹配证据；回跳插件详情的
//  导航目的地由 E4 统一接线，本轮 AssociationRow 不挂插件导航。
//

import SwiftUI
import Core

struct ApplicationDetailView: View {
    let detail: ApplicationDetailEntry
    /// 关联行导航路由；默认纯展示，根视图注入 App → 插件方向路由。
    var associationRoute: (PluginAssociationEntry) -> PluginNavigationRoute? = { _ in nil }

    var body: some View {
        List {
            Section("Application") {
                LabeledContent("Name", value: detail.displayName)
                LabeledContent("Bundle ID", value: detail.bundleIdentifier)
                if let executable = detail.executable {
                    LabeledContent("Executable", value: executable)
                }
                if let version = detail.version {
                    LabeledContent("Version", value: version)
                }
                LabeledContent("System App", value: detail.isSystem ? "Yes" : "No")
            }

            Section("Plugin Associations") {
                LabeledContent("Exact Matches", value: "\(detail.exactMatchCount)")
                PluginAssociationSection(associations: detail.associations, route: associationRoute)
            }
        }
        .navigationTitle(detail.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("detail.app.\(detail.id)")
    }
}
