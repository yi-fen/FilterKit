//
//  PluginFeatureRootView.swift
//  FilterKit 0.1-E4 Plugin Feature Integration & Dependency
//
//  插件功能唯一根视图：单一 NavigationStack + 统一路由解析。插件列表 / 插件
//  详情 / App 列表 / App 详情均为内部页面，不单独开 Tab；目的地解析收口在本
//  视图，E2/E3 ViewModel 不持有 Repository、不各自建导航容器。
//

import SwiftUI
import Core

struct PluginFeatureRootView: View {
    let store: PluginFeatureStore
    @State private var path: [PluginNavigationRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            PluginBrowserView(store: store)
                .navigationDestination(for: PluginNavigationRoute.self) { route in
                    destination(for: route)
                }
        }
        .onAppear {
            // 守卫保证初次进入只扫描一次；子页面 onAppear 不触发 refresh。
            store.loadIfNeeded()
        }
    }

    @ViewBuilder
    private func destination(for route: PluginNavigationRoute) -> some View {
        switch route {
        case .plugin(let id):
            if let detail = store.pluginDetail(id: id) {
                PluginDetailView(detail: detail) { association in
                    association.applicationID.map { .application($0) }
                }
            } else {
                missingDataView
            }
        case .application(let id):
            if let detail = store.applicationDetail(id: id) {
                ApplicationDetailView(detail: detail) { association in
                    .plugin(association.pluginID)
                }
            } else {
                missingDataView
            }
        case .applicationList:
            ApplicationListView(entries: store.applicationDetails)
        }
    }

    private var missingDataView: some View {
        ContentUnavailableView(
            "Record Not Found",
            systemImage: "questionmark.folder",
            description: Text("The current snapshot does not contain the requested record.")
        )
    }
}

#Preview {
    PluginFeatureRootView(
        store: PluginFeatureStore(
            repository: DiagnosticPluginRepository(engine: ReadOnlyDiagnosticsEngine())
        )
    )
}
