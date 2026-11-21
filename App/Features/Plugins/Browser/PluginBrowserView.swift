//
//  PluginBrowserView.swift
//  FilterKit 0.1-E2 Plugin List & Discovery（0.1-E4 接真实数据）
//
//  列表 / 搜索 / 筛选 / 排序展示；数据来自共享 PluginFeatureStore，视图不创建
//  Repository、不触发扫描。导航由根视图单一 NavigationStack 统一挂接；
//  搜索 / 筛选 / 跳转均不重复扫描。
//

import SwiftUI
import Core

struct PluginBrowserView: View {
    let store: PluginFeatureStore
    @State private var viewModel: PluginBrowserViewModel
    @State private var showsFilter = false

    init(store: PluginFeatureStore) {
        self.store = store
        self._viewModel = State(initialValue: PluginBrowserViewModel())
    }

    var body: some View {
        content
            .navigationTitle("Plugins")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        NavigationLink(value: PluginNavigationRoute.applicationList) {
                            Image(systemName: "app.dashed")
                        }
                        Button {
                            showsFilter = true
                        } label: {
                            Image(systemName: "line.3.horizontal.decrease")
                        }
                    }
                }
            }
            .sheet(isPresented: $showsFilter) {
                PluginFilterView(filter: $viewModel.filter)
            }
            .onAppear {
                viewModel.setEntries(store.pluginEntries)
            }
            .onChange(of: store.pluginEntries) { _, entries in
                viewModel.setEntries(entries)
            }
            .onChange(of: viewModel.searchText) { _, _ in viewModel.applyQuery() }
            .onChange(of: viewModel.filter) { _, _ in viewModel.applyQuery() }
            .onChange(of: viewModel.sort) { _, _ in viewModel.applyQuery() }
    }

    @ViewBuilder private var content: some View {
        switch store.state {
        case .neverLoaded, .loading:
            ProgressView("Reading plugin data")
        case .failed(let message):
            ContentUnavailableView(
                "Unable to read plugins",
                systemImage: "exclamationmark.triangle",
                description: Text(message)
            )
        case .empty:
            emptyContent
        case .loaded:
            loadedContent
        }
    }

    @ViewBuilder private var loadedContent: some View {
        VStack(spacing: 8) {
            if let refreshError = store.lastRefreshError {
                refreshWarning(refreshError)
            }
            PluginSearchBar(
                text: $viewModel.searchText,
                prompt: "Search plugins, file name or Bundle ID"
            )
            if viewModel.entries.isEmpty {
                searchEmptyContent
            } else {
                List(viewModel.entries) { entry in
                    NavigationLink(value: PluginNavigationRoute.plugin(entry.id)) {
                        PluginBrowserRow(entry: entry)
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .padding(.horizontal)
    }

    private func refreshWarning(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.footnote)
            .foregroundColor(.orange)
            .padding(8)
            .background(.secondary.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var emptyContent: some View {
        ContentUnavailableView(
            "No Plugins",
            systemImage: "puzzlepiece.extension",
            description: Text("No plugin records in the current diagnostic data.")
        )
    }

    private var searchEmptyContent: some View {
        ContentUnavailableView.search(text: viewModel.searchText)
    }
}

#Preview {
    PluginBrowserView(
        store: PluginFeatureStore(
            repository: DiagnosticPluginRepository(engine: ReadOnlyDiagnosticsEngine())
        )
    )
}
