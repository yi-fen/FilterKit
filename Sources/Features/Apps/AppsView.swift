import SwiftUI
import UIKit
import UniformTypeIdentifiers
import Combine

@MainActor
private final class AppsViewModel: ObservableObject {
    @Published private(set) var apps: [InstalledApp] = []
    @Published private(set) var associatedBundleIDs: Set<String> = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorKey: String?
    @Published private(set) var scannedAt: Date?

    private let appProvider: CachedAppDiscoveryProvider
    private var pluginRegistryCancellable: AnyCancellable?
    private var inventoryRefreshCancellable: AnyCancellable?

    init() {
        appProvider = AppDiscoveryProviderRegistry.shared
        // Associations consume the shared plugin snapshot. A nil snapshot starts
        // the registry's normal background scan; Apps never creates a second scanner.
        let registry = PluginScanRegistry.shared
        pluginRegistryCancellable = registry.$result
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.loadAssociationsFromSharedSnapshot()
                }
            }
        inventoryRefreshCancellable = NotificationCenter.default
            .publisher(for: .filterKitAppInventoryDidRefresh)
            .compactMap { $0.object as? [InstalledApp] }
            .sink { [weak self] refreshedApps in
                Task { @MainActor [weak self] in
                    self?.apps = refreshedApps
                    self?.scannedAt = Date()
                    self?.errorKey = nil
                }
            }
        AppDiscoveryProviderRegistry.startObservingSystemChanges()
        // R16-aligned: read any warm inventory synchronously from the initializer so
        // the first frame can render the list before `.task` resumes the load. Nil on
        // a first cold launch; the inline loading row stays the honest fallback then.
        apps = appProvider.currentSnapshotSync() ?? []
    }

    func recordPageEntry() {
        let hasWarmInventory = appProvider.currentSnapshotSync() != nil
        AppDiscoveryPerformanceDiagnostics.recordAppPageEntry(warmInventory: hasWarmInventory)
        AppDiscoveryPerformanceDiagnostics.logSummaryIfNeeded()
    }

    func load(forceRefresh: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        // First paint: show any warm cached inventory before the background
        // scan/refresh completes. A first cold launch with no snapshot still
        // renders the loading state until the inventory arrives.
        if apps.isEmpty, let snapshot = await appProvider.currentSnapshot() {
            apps = snapshot
        }
        do {
            let inventory: [InstalledApp]
            if forceRefresh { inventory = try await appProvider.refreshInstalledApps() }
            else { inventory = try await appProvider.scanInstalledApps() }
            apps = inventory
            scannedAt = Date()
            errorKey = nil
            // Association resolution is a background complement: the app list stays
            // visible once the inventory lands; matched bundle IDs back-fill later.
            await loadAssociationsFromSharedSnapshot()
        } catch let error as AppDiscoveryError {
            errorKey = Self.localizationKey(for: error)
        } catch {
            errorKey = "app_discovery.enumeration_unavailable"
        }
    }

    private func loadAssociationsFromSharedSnapshot() async {
        let registry = PluginScanRegistry.shared
        guard let scan = registry.result else {
            AppDiscoveryPerformanceDiagnostics.recordPluginSnapshot(hit: false)
            registry.loadIfNeeded()
            return
        }
        AppDiscoveryPerformanceDiagnostics.recordPluginSnapshot(hit: true)
        PluginInventoryPerformanceDiagnostics.recordAssociationSnapshotConsumption()
        // Association matching is a pure join over the already-published App and
        // Plugin inventories. If App inventory is not ready yet, defer instead of
        // launching a second LaunchServices enumeration from the association path.
        guard let snapshot = await appProvider.currentSnapshot() else {
            PluginInventoryPerformanceDiagnostics.recordAssociationDeferredForAppSnapshot()
            return
        }
        do {
            let reader = ReadOnlyPluginAssociationReader(
                appDiscoveryProvider: appProvider, snapshotApps: snapshot)
            let associations = try await reader.readAssociations(from: scan)
            associatedBundleIDs = Set(associations.snapshots.flatMap(\.effectiveBundleIdentifiers))
            AppDiscoveryPerformanceDiagnostics.logSummaryIfNeeded()
            PluginInventoryPerformanceDiagnostics.logSummaryIfNeeded()
        } catch {
            // App inventory remains useful if association resolution is unavailable.
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
    @State private var showingAssociatedOnly = false

    private var visibleApps: [InstalledApp] {
        let inventory = AppInventoryQuery.filter(model.apps, searchText: searchText,
                                                 showingSystemApps: showingSystemApps)
        guard showingAssociatedOnly else { return inventory }
        return inventory.filter { model.associatedBundleIDs.contains($0.bundleIdentifier) }
    }

    var body: some View {
        NavigationView {
            Group {
                if model.isLoading && model.apps.isEmpty {
                    // First scan: list frame renders first with an inline progress
                    // row instead of a full-screen loading transition.
                    List {
                        Section {
                            HStack(spacing: 12) {
                                ProgressView()
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("apps.loading.title").font(.headline)
                                    Text("apps.loading.message").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .listStyle(InsetGroupedListStyle())
                    .refreshable { await model.load(forceRefresh: true) }
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
                                NavigationLink(destination: AppDetailView(app: app)) {
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
                    Button { showingAssociatedOnly.toggle() } label: {
                        Image(systemName: showingAssociatedOnly ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel(showingAssociatedOnly ? "apps.filter.all" : "apps.filter.associated")
                    .accessibilityValue(showingAssociatedOnly ? "apps.filter.associated" : "apps.filter.all")
                    .accessibilityIdentifier("apps.filter.toggle")
                }
            }
            .onAppear { model.recordPageEntry() }
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
            ApplicationIconView(bundleIdentifier: app.bundleIdentifier, descriptor: app.iconDescriptor, classification: app.systemClassification)
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

private struct AppDetailView: View {
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
                if let url = app.bundleURL { AppDetailValueRow(title: "apps.detail.path", value: url.path) }
            }
            AppDetailPluginManagementSection(app: app)
        }
        .listStyle(.insetGrouped)
        .navigationTitle(app.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// App-scoped plugin inventory and import entry point. Import currently performs
/// file selection and a read-only review only; deployment remains behind the
/// production release gate until RootHide device acceptance is complete.
private struct AppDetailPluginManagementSection: View {
    let app: InstalledApp
    @ObservedObject private var registry = PluginScanRegistry.shared
    @State private var isImportingPlugin = false
    @State private var importedFileNames: [String] = []
    @State private var showingImportReview = false

    private var relatedPlugins: [PluginScanItem] {
        let items = registry.result?.plugins ?? []
        return items.filter { plugin in
            if plugin.hardBoundBundleIdentifier == app.bundleIdentifier { return true }
            if plugin.softAssociatedBundleIdentifiers.contains(app.bundleIdentifier) { return true }
            if let bundles = plugin.filterConfiguration?.bundles,
               bundles.contains("*") || bundles.contains(app.bundleIdentifier) { return true }
            return false
        }.sorted { $0.baseName.localizedStandardCompare($1.baseName) == .orderedAscending }
    }

    private var hardBoundPlugins: [PluginScanItem] {
        relatedPlugins.filter { $0.hardBoundBundleIdentifier == app.bundleIdentifier }
    }

    private var softAssociatedPlugins: [PluginScanItem] {
        relatedPlugins.filter { $0.hardBoundBundleIdentifier != app.bundleIdentifier
            && $0.softAssociatedBundleIdentifiers.contains(app.bundleIdentifier) }
    }

    private var filterMatchedPlugins: [PluginScanItem] {
        relatedPlugins.filter { plugin in
            plugin.hardBoundBundleIdentifier != app.bundleIdentifier
                && !plugin.softAssociatedBundleIdentifiers.contains(app.bundleIdentifier)
        }
    }

    private var manageableCount: Int {
        relatedPlugins.compactMap { activationState(for: $0) }.filter(\.canPreviewToggle).count
    }

    var body: some View {
        Section {
            // Prominent, always-visible app-detail import action (not hidden in a menu).
            Button { isImportingPlugin = true } label: {
                Label("apps.detail.import_plugin", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier("apps.detail.import_plugin")

            HStack {
                Label("apps.detail.manageable_plugins", systemImage: "puzzlepiece.extension")
                Spacer()
                Text("\(manageableCount)").foregroundStyle(.secondary)
            }
            if registry.isLoading && registry.result == nil {
                HStack { ProgressView(); Text("plugins.loading.message").font(.footnote).foregroundStyle(.secondary) }
            } else if registry.isLoading {
                HStack { ProgressView().controlSize(.small); Text("apps.detail.refreshing_plugins").font(.caption).foregroundStyle(.secondary) }
            } else if registry.result?.directoryState != .resolved {
                Label("apps.detail.plugin_inventory_unavailable", systemImage: "exclamationmark.triangle")
                    .font(.footnote).foregroundStyle(.secondary)
            } else if relatedPlugins.isEmpty {
                Text("apps.detail.no_related_plugins").font(.footnote).foregroundStyle(.secondary)
            } else {
                if !hardBoundPlugins.isEmpty {
                    Text("apps.detail.hard_bound_plugins").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(hardBoundPlugins) { plugin in pluginRow(plugin) }
                }
                if !softAssociatedPlugins.isEmpty {
                    Text("apps.detail.soft_associated_plugins").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(softAssociatedPlugins) { plugin in pluginRow(plugin) }
                }
                if !filterMatchedPlugins.isEmpty {
                    Text("apps.detail.filter_matched_plugins").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(filterMatchedPlugins) { plugin in pluginRow(plugin) }
                }
            }
            Label("apps.detail.plugin_mutations_locked", systemImage: "lock.shield")
                .font(.caption).foregroundStyle(.secondary)
        } header: {
            HStack {
                Text("apps.detail.plugins")
                Spacer()
                Button("apps.detail.refresh_plugins") { registry.refresh() }
                    .font(.caption)
                    .textCase(nil)
            }
        }
        .task { registry.loadIfNeeded() }
        .fileImporter(isPresented: $isImportingPlugin,
                      allowedContentTypes: [UTType(filenameExtension: "dylib", conformingTo: .data) ?? .data,
                                            UTType(filenameExtension: "plist", conformingTo: .xml) ?? .xml],
                      allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                importedFileNames = urls.map(\.lastPathComponent)
                showingImportReview = true
            case .failure:
                importedFileNames = []
            }
        }
        .alert("apps.detail.import_review_title", isPresented: $showingImportReview) {
            Button("common.ok", role: .cancel) { importedFileNames = [] }
        } message: {
            Text(String(format: NSLocalizedString("apps.detail.import_review_message", comment: ""), importedFileNames.joined(separator: "\n")))
        }
    }

    @ViewBuilder
    private func pluginRow(_ plugin: PluginScanItem) -> some View {
        if let activation = activationState(for: plugin) {
            AppScopedPluginRow(plugin: plugin, app: app, activation: activation)
                .accessibilityIdentifier("apps.detail.plugin.\(plugin.id)")
        }
    }

    private func activationState(for plugin: PluginScanItem) -> AppPluginActivationState? {
        AppPluginActivationStateResolver().resolve(
            plugin: plugin, targetBundleIdentifier: app.bundleIdentifier,
            targetAppIsAvailable: true)
    }
}

private struct AppScopedPluginRow: View {
    let plugin: PluginScanItem
    let app: InstalledApp
    let activation: AppPluginActivationState
    @ObservedObject private var operationStore = AppPluginActivationOperationStore.shared
    @ObservedObject private var registry = PluginScanRegistry.shared
    @State private var showingCommitConfirmation = false
    @State private var showingOperationNotice = false

    private var snapshotRevision: UInt64 { registry.snapshotRevision }
    private var operationBelongsToRow: Bool {
        operationStore.pending?.command.pluginID == UUID(uuidString: plugin.filterKitPluginID ?? "") &&
        operationStore.pending?.command.targetBundleIdentifier == app.bundleIdentifier
    }

    var body: some View {
        HStack(spacing: 10) {
            NavigationLink(destination: AppScopedPluginDetailView(plugin: plugin, app: app)) {
                HStack(spacing: 10) {
                    Image(systemName: "puzzlepiece.extension.fill").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(plugin.baseName).font(.body.weight(.medium))
                        Text(plugin.dylibFileName ?? plugin.plistFileName ?? plugin.id)
                            .font(.caption).foregroundStyle(.secondary)
                        Label(associationTitle, systemImage: activation.isHardBound ? "pin.fill" : "link")
                            .font(.caption2).foregroundStyle(.secondary)
                        Text(observedStateTitle).font(.caption2).foregroundStyle(.secondary)
                        if let reason = activation.readOnlyReasonKey {
                            Text(LocalizedStringKey(reason)).font(.caption2).foregroundStyle(.secondary)
                        }
                        if operationBelongsToRow {
                            Text(operationStatusKey)
                                .font(.caption2).foregroundStyle(.orange)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            Toggle("apps.detail.activation_toggle_accessibility", isOn: Binding(
                get: { activation.isEnabled ?? false },
                set: { newValue in
                    Task {
                        await operationStore.prepare(plugin: plugin, activation: activation,
                            desiredEnabled: newValue, snapshotRevision: snapshotRevision)
                        if operationBelongsToRow && operationStore.phase == .prepared {
                            showingCommitConfirmation = true
                        } else {
                            showingOperationNotice = true
                        }
                    }
                }))
                .labelsHidden()
                .disabled(!activation.canPreviewToggle || operationStore.phase == .preparing || operationStore.phase == .committing)
                .accessibilityIdentifier("apps.detail.activation.toggle.\(plugin.id).\(app.bundleIdentifier)")
                .accessibilityLabel(Text("\(plugin.baseName) — \(app.displayName)"))
        }
        .padding(.vertical, 3)
        .onChange(of: snapshotRevision) { _ in
            operationStore.invalidatePending()
        }
        .confirmationDialog("apps.detail.activation_confirm_title", isPresented: $showingCommitConfirmation,
                            titleVisibility: .visible) {
            Button("apps.detail.activation_confirm_action", role: .destructive) {
                Task {
                    await operationStore.commit(userConfirmed: true, currentSnapshotRevision: snapshotRevision)
                    showingOperationNotice = true
                }
            }
            Button("common.ok", role: .cancel) { operationStore.invalidatePending(reason: "user_cancelled") }
        } message: {
            Text("apps.detail.activation_confirm_message")
        }
        .alert("apps.detail.activation_operation_title", isPresented: $showingOperationNotice) {
            Button("common.ok", role: .cancel) { }
        } message: {
            Text(operationStatusKey)
        }
    }

    private var operationStatusKey: LocalizedStringKey {
        switch operationStore.phase {
        case .idle: return "apps.detail.activation_operation_idle"
        case .preparing: return "apps.detail.activation_operation_preparing"
        case .prepared: return "apps.detail.activation_operation_prepared"
        case .committing: return "apps.detail.activation_operation_committing"
        case .committed: return "apps.detail.activation_operation_committed_refreshing"
        case .blocked: return "apps.detail.activation_operation_release_closed"
        case .outcomeUnknown: return "apps.detail.activation_operation_unknown"
        case .failed: return "apps.detail.activation_operation_failed"
        }
    }

    private var associationTitle: LocalizedStringKey {
        switch activation.associationKind {
        case .hardBound: return "apps.detail.activation_hard_bound"
        case .softAssociated: return "apps.detail.activation_soft_associated"
        case .filterMatched: return "apps.detail.activation_filter_match"
        }
    }

    private var observedStateTitle: LocalizedStringKey {
        switch activation.observedState {
        case .enabled: return "apps.detail.activation_enabled"
        case .disabled: return "apps.detail.activation_disabled"
        case .globalFilter: return "apps.detail.activation_global"
        case .ambiguousFilter: return "apps.detail.activation_ambiguous"
        case .inconsistent: return "apps.detail.activation_mismatch"
        case .unavailable: return "apps.detail.activation_unavailable"
        }
    }
}

private struct AppScopedPluginDetailView: View {
    let plugin: PluginScanItem
    let app: InstalledApp

    var body: some View {
        List {
            Section("apps.detail.plugin_information") {
                AppDetailValueRow(title: "plugins.detail.name", value: plugin.baseName)
                AppDetailValueRow(title: "plugins.detail.ownership", value: plugin.ownership.rawValue)
                AppDetailValueRow(title: "plugins.detail.pairing", value: plugin.pairingState.rawValue)
                AppDetailValueRow(title: "apps.detail.target_app", value: app.displayName)
                AppDetailValueRow(title: "apps.detail.bundle_id", value: app.bundleIdentifier)
                if let file = plugin.dylibFileName { AppDetailValueRow(title: "plugins.detail.dylib", value: file) }
                if let file = plugin.plistFileName { AppDetailValueRow(title: "plugins.detail.plist", value: file) }
            }
            Section {
                Label("apps.detail.plugin_mutations_locked", systemImage: "lock.shield")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("apps.detail.plugin_detail_read_only").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(plugin.baseName)
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
