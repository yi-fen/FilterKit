//
//  ApplicationListView.swift
//  FilterKit 0.1-E3 Plugin Detail & App Association Explorer
//
//  诊断发现的 App 列表；行点击经统一路由进入 App 详情。列表数据由共享
//  Store 快照投影注入，不接 Repository、不取合成桩。
//

import SwiftUI
import Core

struct ApplicationListView: View {
    let entries: [ApplicationDetailEntry]

    var body: some View {
        List {
            if entries.isEmpty {
                ContentUnavailableView(
                    "No Applications",
                    systemImage: "app.dashed",
                    description: Text("No application records in the current diagnostic data.")
                )
            } else {
                ForEach(entries) { entry in
                    NavigationLink(value: PluginNavigationRoute.application(entry.id)) {
                        ApplicationRow(entry: entry)
                    }
                }
            }
        }
        .navigationTitle("Applications")
    }
}
