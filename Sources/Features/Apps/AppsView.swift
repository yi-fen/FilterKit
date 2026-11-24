import SwiftUI
import UIKit

private enum AppsFilter: String, CaseIterable, Identifiable {
    case all
    case associated
    var id: String { rawValue }
    var titleKey: LocalizedStringKey { self == .all ? "apps.filter.all" : "apps.filter.associated" }
}

@MainActor
private final class AppsViewModel: ObservableObject {
    @Published private(set) var apps: [InstalledApp] = []
    @Published private(set) var associatedBundleIDs: Set<String> = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorKey: String?
    @Published private(set) var scannedAt: Date?

    private let appProvider: CachedAppDiscoveryProvider
    private let environmentProvider: ReadOnlyEnvironmentProvider

    init() {
        let discovery = LaunchServicesAppDiscoveryProvider()
        appProvider = CachedAppDiscoveryProvider(source: discovery)
        environmentProvider = ReadOnlyEnvironmentProvider()
    }

    func load(forceRefresh: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let inventory: [InstalledApp]
            if forceRefresh { inventory = try await appProvider.refreshInstalledApps() }
            else { inventory = try await appProvider.scanInstalledApps() }
            apps = inventory
            scannedAt = Date()
            errorKey = nil
            await loadAssociations(using: appProvider)
        } catch let error as AppDiscoveryError {
            errorKey = Self.localizationKey(for: error)
        } catch {
            errorKey = "app_discovery.enumeration_unavailable"
        }
    }

    private func loadAssociations(using discovery: AppDiscoveryProvider) async {
        do {
            let report = environmentProvider.makeDiagnosticReport()
            guard let assessment = report.pluginDirectoryAssessment else {
                associatedBundleIDs = []
                return
            }
            let scanner = ReadOnlyPluginScanner(assessmentProvider: { assessment })
            let scan = try await scanner.scanPlugins()
            let reader = ReadOnlyPluginAssociationReader(appDiscoveryProvider: discovery)
            let associations = try await reader.readAssociations(from: scan)
            associatedBundleIDs = Set(associations.snapshots.flatMap { snapshot in
                snapshot.effectiveBundleIdentifiers
            })
        } catch {
            // App discovery remains useful if plugin-directory inspection is unavailable.
            associatedBundleIDs = []
        }
    }

    private static func localizationKey(for error: AppDiscoveryError) -> String {
        switch error {
        case .launchServicesUnavailable: return "app_discovery.launch_services_unavailable"
        case .workspaceUnavailable: return "app_discovery.workspace_unavailable"
        case .enumerationUnavailable: return "app_discovery.enumeration_unavailable"
        case .accessRestricted: return "app_discovery.access_restricted"
        case .lsdProcessGuard: return "app_discovery.lsd_guard"
        case .noReadableInventory: return "app_discovery.no_readable_inventory"
        }
    }
}

struct AppsView: View {
    @AppStorage("filterkit.showSystemApps") private var showingSystemApps = false
    @StateObject private var model = AppsViewModel()
    @State private var searchText = ""
    @State private var filter: AppsFilter = .all

    private var visibleApps: [InstalledApp] {
        let inventory = AppInventoryQuery.filter(model.apps, searchText: searchText,
                                                 showingSystemApps: showingSystemApps)
        guard filter == .associated else { return inventory }
        return inventory.filter { model.associatedBundleIDs.contains($0.bundleIdentifier) }
    }

    var body: some View {
        NavigationView {
            Group {
                if model.isLoading && model.apps.isEmpty {
                    FKStateView(kind: .loading, systemImage: "square.grid.2x2",
                                title: "apps.loading.title", message: "apps.loading.message")
                } else if let error = model.errorKey, model.apps.isEmpty {
                    FKStateView(kind: .error, systemImage: "exclamationmark.triangle",
                                title: "apps.error.title", message: LocalizedStringKey(error),
                                actionTitle: "app_discovery.refresh") {
                        Task { await model.load(forceRefresh: true) }
                    }
                } else if visibleApps.isEmpty {
                    FKStateView(kind: .empty, systemImage: "app.dashed",
                                title: searchText.isEmpty ? "apps.empty.title" : "apps.empty.search_title",
                                message: searchText.isEmpty ? "apps.empty.message" : "apps.empty.search_message",
                                actionTitle: "app_discovery.refresh") {
                        Task { await model.load(forceRefresh: true) }
                    }
                } else {
                    List {
                        Section {
                            ForEach(visibleApps) { app in
                                NavigationLink(destination: AppDetailPlaceholderView(app: app)) {
                                    AppRow(app: app, isAssociated: model.associatedBundleIDs.contains(app.bundleIdentifier))
                                }
                            }
                        } header: {
                            HStack {
                                Text("apps.count")
                                Spacer()
                                Text("\(visibleApps.count)")
                            }
                        }
                    }
                    .listStyle(InsetGroupedListStyle())
                    .refreshable { await model.load(forceRefresh: true) }
                }
            }
            .navigationTitle("tab.apps")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: Text("app_discovery.search_placeholder"))
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Picker("apps.filter.title", selection: $filter) {
                            ForEach(AppsFilter.allCases) { item in Text(item.titleKey).tag(item) }
                        }
                        Divider()
                        Button { Task { await model.load(forceRefresh: true) } } label: {
                            Label("app_discovery.refresh", systemImage: "arrow.clockwise")
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityIdentifier("apps.filter.menu")
                }
            }
            .task { await model.load() }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

private struct AppRow: View {
    let app: InstalledApp
    let isAssociated: Bool

    var body: some View {
        HStack(spacing: 12) {
            ApplicationIconView(descriptor: app.iconDescriptor, classification: app.systemClassification)
            VStack(alignment: .leading, spacing: 4) {
                Text(app.displayName).font(.body.weight(.medium)).foregroundColor(.primary)
                Text(app.bundleIdentifier).font(.caption).foregroundColor(.secondary).lineLimit(1)
                if app.systemClassification == .system {
                    Text("apps.badge.system").font(.caption2).foregroundColor(.secondary)
                }
            }
            Spacer(minLength: 4)
            if isAssociated {
                Image(systemName: "puzzlepiece.extension.fill")
                    .foregroundColor(FilterKitTheme.ColorToken.accent)
                    .accessibilityLabel(Text("apps.badge.associated"))
            }
        }
        .padding(.vertical, 3)
    }
}

private struct AppDetailPlaceholderView: View {
    let app: InstalledApp
    var body: some View {
        List {
            Section(header: Text("apps.detail.information")) {
                AppDetailValueRow(title: "apps.detail.name", value: app.displayName)
                AppDetailValueRow(title: "apps.detail.bundle_id", value: app.bundleIdentifier)
                AppDetailValueRow(title: "apps.detail.type", value: app.systemClassification.rawValue)
                if let version = app.shortVersion { AppDetailValueRow(title: "apps.detail.version", value: version) }
                if let build = app.buildVersion { AppDetailValueRow(title: "apps.detail.build", value: build) }
                if let executable = app.executableName { AppDetailValueRow(title: "apps.detail.executable", value: executable) }
                AppDetailValueRow(title: "apps.detail.discovery_source", value: app.discoverySource.rawValue)
                if let url = app.bundleURL {
                    AppDetailValueRow(title: "apps.detail.path", value: url.path)
                }
            }
            Section {
                Text("apps.detail.import_placeholder").foregroundColor(.secondary)
            } header: { Text("apps.detail.plugins") }
        }
        .navigationTitle(app.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AppDetailValueRow: View {
    let title: LocalizedStringKey
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundColor(.secondary)
            Text(value).font(.body).textSelection(.enabled)
        }
        .padding(.vertical, 3)
    }
}
