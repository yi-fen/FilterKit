import SwiftUI

@MainActor
private final class HomeDashboardModel: ObservableObject {
    @Published private(set) var installedAppCount = 0
    @Published private(set) var environmentStatusKey = "home.status.checking"
    @Published private(set) var elleKitVersion = "—"
    @Published private(set) var lastScanDate: Date?
    @Published private(set) var isRefreshing = false

    let plugins = PluginScanRegistry.shared
    private let apps = AppDiscoveryProviderRegistry.shared

    var pluginCount: Int { plugins.result?.plugins.count ?? 0 }
    var filterCount: Int { plugins.result?.plugins.filter { $0.plistFileName != nil }.count ?? 0 }
    var parsedFilterCount: Int {
        plugins.result?.plugins.filter { $0.filterConfiguration?.parseState == .valid }.count ?? 0
    }
    var invalidFilterCount: Int {
        plugins.result?.plugins.filter {
            $0.filterConfiguration?.parseState == .invalid || $0.filterConfiguration?.parseState == .partial
        }.count ?? 0
    }
    var associatedAppCount: Int {
        let ids = plugins.result?.plugins.flatMap { item in
            ([item.hardBoundBundleIdentifier].compactMap { $0 }) + item.softAssociatedBundleIdentifiers
        } ?? []
        return Set(ids).count
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        plugins.refresh()
        do {
            let inventory = try await apps.refreshInstalledApps()
            installedAppCount = inventory.count
        } catch {
            if let snapshot = await apps.currentSnapshot() { installedAppCount = snapshot.count }
        }
        let provider = ReadOnlyEnvironmentProvider()
        let report = await Task.detached(priority: .utility) { provider.makeDiagnosticReport() }.value
        if report.rootValidation.validatedRootPath != nil {
            environmentStatusKey = report.elleKitAssessment?.installationState == .installed
                ? "home.status.ellekit_detected" : "home.status.root_detected_ellekit_uncertain"
        } else {
            environmentStatusKey = "home.status.environment_unresolved"
        }
        elleKitVersion = report.elleKitAssessment?.packageMetadata?.version ?? "—"
        lastScanDate = plugins.result?.scannedAt
    }

    func load() async {
        plugins.loadIfNeeded()
        if let snapshot = await apps.currentSnapshot() { installedAppCount = snapshot.count }
        else {
            do { installedAppCount = (try await apps.scanInstalledApps()).count }
            catch { installedAppCount = 0 }
        }
        let provider = ReadOnlyEnvironmentProvider()
        let report = await Task.detached(priority: .utility) { provider.makeDiagnosticReport() }.value
        if report.rootValidation.validatedRootPath != nil {
            environmentStatusKey = report.elleKitAssessment?.installationState == .installed
                ? "home.status.ellekit_detected" : "home.status.root_detected_ellekit_uncertain"
        } else {
            environmentStatusKey = "home.status.environment_unresolved"
        }
        elleKitVersion = report.elleKitAssessment?.packageMetadata?.version ?? "—"
        lastScanDate = plugins.result?.scannedAt
    }
}

struct HomeView: View {
    @StateObject private var model = HomeDashboardModel()
    @ObservedObject private var pluginRegistry = PluginScanRegistry.shared

    var body: some View {
        NavigationView {
            List {
                Section("home.overview") {
                    HStack(spacing: 12) {
                        metric("home.apps", value: model.installedAppCount, symbol: "app")
                        metric("home.plugins", value: model.pluginCount, symbol: "puzzlepiece.extension")
                    }
                    HStack(spacing: 12) {
                        metric("home.filters", value: model.filterCount, symbol: "line.3.horizontal.decrease.circle")
                        metric("home.associated_apps", value: model.associatedAppCount, symbol: "link")
                    }
                }
                Section("home.filter_health") {
                    dashboardRow("home.filter.parsed", value: "\(model.parsedFilterCount)", symbol: "checkmark.circle.fill")
                    dashboardRow("home.filter.invalid", value: "\(model.invalidFilterCount)", symbol: "exclamationmark.triangle")
                    if pluginRegistry.result == nil {
                        HStack { ProgressView(); Text("home.scan.pending").font(.footnote).foregroundStyle(.secondary) }
                    }
                }
                Section("home.environment") {
                    HStack {
                        Label("home.environment.status", systemImage: "shield.lefthalf.filled")
                        Spacer()
                        Text(LocalizedStringKey(model.environmentStatusKey)).foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Label("home.environment.ellekit_version", systemImage: "shippingbox")
                        Spacer()
                        Text(model.elleKitVersion).foregroundStyle(.secondary)
                    }
                }
                Section {
                    HStack {
                        Label("home.last_scan", systemImage: "clock")
                        Spacer()
                        Text((pluginRegistry.result?.scannedAt ?? model.lastScanDate).map { DateFormatter.localizedString(from: $0, dateStyle: .short, timeStyle: .short) } ?? "—")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Button {
                        Task { await model.refresh() }
                    } label: {
                        HStack {
                            Label("home.refresh", systemImage: "arrow.clockwise")
                            Spacer()
                            if model.isRefreshing { ProgressView() }
                        }
                    }
                    .disabled(model.isRefreshing)
                }
                Section {
                    Label("home.operation_hint", systemImage: "info.circle")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("tab.home")
            .navigationBarTitleDisplayMode(.large)
            .refreshable { await model.refresh() }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .task { await model.load() }
    }

    private func metric(_ title: LocalizedStringKey, value: Int, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
            Text("\(value)").font(.title2.weight(.semibold)).foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(FilterKitTheme.ColorToken.secondaryBackground, in: RoundedRectangle(cornerRadius: 12))
    }

    private func dashboardRow(_ title: LocalizedStringKey, value: String, symbol: String) -> some View {
        HStack {
            Label(title, systemImage: symbol)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }
}
