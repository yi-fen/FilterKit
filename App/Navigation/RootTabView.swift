//
//  RootTabView.swift
//  FilterKit App 底部 Tab 容器（Stage 2.3 GUI Foundation）
//

import SwiftUI

struct RootTabView: View {
    let dependencies: AppDependencies

    var body: some View {
        TabView {
            DashboardView(dependencies: dependencies)
                .accessibilityIdentifier("tab.dashboard")
                .tabItem {
                    Label(AppTab.dashboard.title, systemImage: AppTab.dashboard.systemImage)
                }

            PluginListView(dependencies: dependencies)
                .accessibilityIdentifier("tab.plugins")
                .tabItem {
                    Label(AppTab.plugins.title, systemImage: AppTab.plugins.systemImage)
                }

            DiagnosticsView(dependencies: dependencies)
                .accessibilityIdentifier("tab.diagnostics")
                .tabItem {
                    Label(AppTab.diagnostics.title, systemImage: AppTab.diagnostics.systemImage)
                }

            SettingsView(dependencies: dependencies)
                .accessibilityIdentifier("tab.settings")
                .tabItem {
                    Label(AppTab.settings.title, systemImage: AppTab.settings.systemImage)
                }
        }
    }
}
