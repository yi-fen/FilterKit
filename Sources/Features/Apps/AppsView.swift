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
                    // Re-join the new App Inventory with the existing shared Plugin
                    // Inventory. This restores/unsets association availability after
                    // install or uninstall without starting another plugin scan.
                    await self?.loadAssociationsFromSharedSnapshot()
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
            associatedBundleIDs = HelperBundleIdentifierKey.set(associations.snapshots.flatMap(\.effectiveBundleIdentifiers))
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
        return inventory.filter { model.associatedBundleIDs.contains(HelperBundleIdentifierKey.make($0.bundleIdentifier)) }
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
                                    AppRow(app: app, isAssociated: model.associatedBundleIDs.contains(HelperBundleIdentifierKey.make(app.bundleIdentifier)))
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
    @State private var importReviewMessage = ""
    @State private var showingImportReview = false

    private var relatedPlugins: [PluginScanItem] {
        let items = registry.result?.plugins ?? []
        let appKey = HelperBundleIdentifierKey.make(app.bundleIdentifier)
        return items.filter { plugin in
            if let owner = plugin.hardBoundBundleIdentifier,
               HelperBundleIdentifierKey.make(owner) == appKey { return true }
            if plugin.softAssociatedBundleIdentifiers.contains(where: {
                HelperBundleIdentifierKey.make($0) == appKey
            }) { return true }
            if let bundles = plugin.filterConfiguration?.bundles,
               bundles.contains("*") || HelperBundleIdentifierKey.set(bundles).contains(appKey) { return true }
            return false
        }.sorted { $0.baseName.localizedStandardCompare($1.baseName) == .orderedAscending }
    }

    private var hardBoundPlugins: [PluginScanItem] {
        relatedPlugins.filter {
            guard let owner = $0.hardBoundBundleIdentifier else { return false }
            return HelperBundleIdentifierKey.make(owner) == HelperBundleIdentifierKey.make(app.bundleIdentifier)
        }
    }

    private var softAssociatedPlugins: [PluginScanItem] {
        relatedPlugins.filter { plugin in
            let ownerMatches = plugin.hardBoundBundleIdentifier.map {
                HelperBundleIdentifierKey.make($0) == HelperBundleIdentifierKey.make(app.bundleIdentifier)
            } ?? false
            return !ownerMatches && plugin.softAssociatedBundleIdentifiers.contains {
                HelperBundleIdentifierKey.make($0) == HelperBundleIdentifierKey.make(app.bundleIdentifier)
            }
        }
    }

    private var filterMatchedPlugins: [PluginScanItem] {
        relatedPlugins.filter { plugin in
            let appKey = HelperBundleIdentifierKey.make(app.bundleIdentifier)
            let ownerMatches = plugin.hardBoundBundleIdentifier.map {
                HelperBundleIdentifierKey.make($0) == appKey
            } ?? false
            let associationMatches = plugin.softAssociatedBundleIdentifiers.contains {
                HelperBundleIdentifierKey.make($0) == appKey
            }
            return !ownerMatches && !associationMatches
        }
    }

    private var manageableCount: Int {
        relatedPlugins.compactMap { activationState(for: $0) }.filter(\.canPreviewToggle).count
    }

    var body: some View {
        Section {
            // Prominent, always-visible app-detail import action (not hidden in a menu).
            Button { isImportingPlugin = true } label: {
                Label("apps.detail.inject_plugin", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier("apps.detail.inject_plugin")

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
                                            UTType(filenameExtension: "plist", conformingTo: .data) ?? .data,
                                            .zip,
                                            UTType(filenameExtension: "deb", conformingTo: .data) ?? .data],
                      allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                inspectSelectedPluginFiles(urls)
            case .failure(let error):
                importReviewMessage = error.localizedDescription
                showingImportReview = true
            }
        }
        .alert("apps.detail.inject_review_title", isPresented: $showingImportReview) {
            Button("common.ok", role: .cancel) { importReviewMessage = "" }
        } message: {
            Text(importReviewMessage)
        }
    }

    private func inspectSelectedZIP(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            importReviewMessage = "FilterKit could not obtain access to the ZIP file. Re-select it and try again."
            showingImportReview = true
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        do {
            let result = try PluginZIPArchiveInspector().inspect(
                archiveURL: url, targetBundleIdentifier: app.bundleIdentifier)
            var lines = [
                "ZIP: \(url.lastPathComponent)",
                "Detected plugins: \(result.plugins.count)",
                "Injection target: \(app.displayName) (\(app.bundleIdentifier))",
                "Binding: This is a read-only package preview. Binding is not committed during inspection."
            ]
            for (index, plugin) in result.plugins.enumerated() {
                let item = plugin.inspection
                lines.append("\n[\(index + 1)] \(item.displayName)")
                lines.append("Archive path: \(plugin.archivePath)")
                lines.append("Binary: \(item.dylibFileName)")
                lines.append("Architectures: \(item.architectures.joined(separator: ", "))")
                lines.append("SHA-256: \(item.dylibSHA256)")
                lines.append(packageSourceDecision(for: item.dylibSHA256))
                lines.append(plugin.matchedPlistArchivePath.map { "Filter.plist: \($0)" }
                    ?? "Filter.plist: automatically generated (minimal Bundles-only)")
                if let author = item.author { lines.append("Author: \(author)") }
                if let version = item.version { lines.append("Version: \(version)") }
                if !item.warnings.isEmpty { lines.append("Warnings: \(item.warnings.joined(separator: "; "))") }
            }
            if !result.warnings.isEmpty { lines.append("\nPackage warnings:\n• " + result.warnings.joined(separator: "\n• ")) }
            lines.append("\nRead-only ZIP inspection only. No plugin files were injected, backed up, or activated.")
            importReviewMessage = lines.joined(separator: "\n")
        } catch {
            importReviewMessage = "ZIP inspection failed: \(error.localizedDescription)"
        }
        showingImportReview = true
    }

    private func inspectSelectedDEB(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            importReviewMessage = "FilterKit could not obtain access to the Debian package. Re-select it and try again."
            showingImportReview = true
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        do {
            let result = try PluginDEBArchiveInspector().inspect(
                packageURL: url, targetBundleIdentifier: app.bundleIdentifier)
            var lines = [
                "DEB: \(url.lastPathComponent)",
                "Package: \(result.packageName ?? "Unknown")",
                "Version: \(result.packageVersion ?? "Unknown")",
                "Architecture: \(result.packageArchitecture ?? "Unknown")",
                "Maintainer: \(result.maintainer ?? "Unknown")",
                "Detected plugins: \(result.plugins.count)",
                "Injection target: \(app.displayName) (\(app.bundleIdentifier))",
                "Binding: Read-only preview; binding is not committed during inspection."
            ]
            for (index, plugin) in result.plugins.enumerated() {
                let item = plugin.inspection
                lines.append("\n[\(index + 1)] \(item.displayName)")
                lines.append("Package path: \(plugin.archivePath)")
                lines.append("Binary: \(item.dylibFileName)")
                lines.append("Architectures: \(item.architectures.joined(separator: ", "))")
                lines.append("SHA-256: \(item.dylibSHA256)")
                lines.append(packageSourceDecision(for: item.dylibSHA256))
                lines.append(plugin.matchedPlistArchivePath.map { "Filter.plist: \($0)" }
                    ?? "Filter.plist: automatically generated (minimal Bundles-only)")
                if !item.warnings.isEmpty { lines.append("Warnings: \(item.warnings.joined(separator: "; "))") }
            }
            if !result.warnings.isEmpty { lines.append("\nPackage warnings:\n• " + result.warnings.joined(separator: "\n• ")) }
            lines.append("\nRead-only DEB inspection only. No package scripts were executed; no files were injected, backed up, or activated.")
            importReviewMessage = lines.joined(separator: "\n")
        } catch {
            importReviewMessage = "DEB inspection failed: \(error.localizedDescription)"
        }
        showingImportReview = true
    }

    private func inspectSelectedPluginFiles(_ urls: [URL]) {
        let zipFiles = urls.filter { $0.pathExtension.lowercased() == "zip" }
        let debFiles = urls.filter { $0.pathExtension.lowercased() == "deb" }
        if !zipFiles.isEmpty || !debFiles.isEmpty {
            guard urls.count == 1, zipFiles.count + debFiles.count == 1 else {
                importReviewMessage = "Select one ZIP or DEB package at a time. Do not mix package archives with individual files."
                showingImportReview = true
                return
            }
            if let zip = zipFiles.first { inspectSelectedZIP(zip) }
            else if let deb = debFiles.first { inspectSelectedDEB(deb) }
            return
        }
        let dylibs = urls.filter { $0.pathExtension.lowercased() == "dylib" }
        let plists = urls.filter { $0.pathExtension.lowercased() == "plist" }
        guard dylibs.count == 1 else {
            importReviewMessage = dylibs.isEmpty
                ? "Select one .dylib file. A matching Filter.plist is optional."
                : "Select exactly one .dylib file per import. Multiple binaries will be supported by package import in a later phase."
            showingImportReview = true
            return
        }
        guard plists.count <= 1 else {
            importReviewMessage = "More than one plist was selected. Select the matching Filter.plist explicitly."
            showingImportReview = true
            return
        }

        let scopedURLs = urls.filter { $0.startAccessingSecurityScopedResource() }
        guard scopedURLs.count == urls.count else {
            scopedURLs.forEach { $0.stopAccessingSecurityScopedResource() }
            importReviewMessage = "FilterKit could not obtain access to every selected file. Re-select the files and try again."
            showingImportReview = true
            return
        }
        defer { scopedURLs.forEach { $0.stopAccessingSecurityScopedResource() } }
        do {
            let pairedPlist = try PluginImportFilePairResolver().resolve(
                dylibURL: dylibs[0], explicitlySelectedPlistURL: plists.first)
            let pairedPlistScopeStarted = pairedPlist?.startAccessingSecurityScopedResource() ?? false
            if pairedPlist != nil && !pairedPlistScopeStarted {
                throw NSError(domain: "FilterKit.PluginImport", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "FilterKit could not access the matched Filter.plist. Select it explicitly and try again."])
            }
            defer { if pairedPlistScopeStarted { pairedPlist?.stopAccessingSecurityScopedResource() } }
            let inspection = try PluginImportInspector().inspect(
                dylibURL: dylibs[0], originalPlistURL: pairedPlist,
                targetBundleIdentifier: app.bundleIdentifier)
            var lines = [
                "Plugin: \(inspection.displayName)",
                "Binary: \(inspection.dylibFileName)",
                "Architectures: \(inspection.architectures.joined(separator: ", "))",
                "Install name: \(inspection.installName ?? "Unknown")",
                "Version: \(inspection.version ?? "Unknown")",
                "SHA-256: \(inspection.dylibSHA256)",
                packageSourceDecision(for: inspection.dylibSHA256),
                inspection.usesGeneratedPlist
                    ? "Filter.plist: generated (minimal Bundles-only)"
                    : "Filter.plist: \(inspection.originalPlistFileName ?? "not supplied")"
            ]
            if pairedPlist != nil && plists.isEmpty {
                lines.append("Filter.plist: automatically matched from the dylib's containing directory.")
            }
            if let author = inspection.author { lines.append("Author: \(author)") }
            if let hash = inspection.originalPlistSHA256 { lines.append("Original plist SHA-256: \(hash)") }
            if let generated = inspection.generatedPlist, let text = String(data: generated, encoding: .utf8) {
                lines.append("Generated Filter.plist preview:\n\(text)")
            }
            if !inspection.warnings.isEmpty {
                lines.append("Warnings:\n• " + inspection.warnings.joined(separator: "\n• "))
            }
            lines.append("\nInjection preview: fixed owner App = \(app.displayName). Additional App associations can be managed later in Plugins.")
            lines.append("Default activation intent: enabled after a successful injection; this inspection does not inject or activate files.")
            lines.append("\nRead-only inspection only. No files were injected or modified.")
            importReviewMessage = lines.joined(separator: "\n")
        } catch {
            importReviewMessage = "Plugin inspection failed: \(error.localizedDescription)"
        }
        showingImportReview = true
    }

    private func packageSourceDecision(for sha256: String) -> String {
        guard let snapshot = PluginScanRegistry.shared.result,
              snapshot.directoryState == .resolved else {
            return "Source check: unavailable. Do not inject until the shared Plugin Inventory is available."
        }
        let normalized = sha256.lowercased()
        if snapshot.plugins.contains(where: {
            $0.ownership == .packageManager && $0.dylibSHA256?.lowercased() == normalized
        }), PluginSourceOperationPolicy.decision(for: .packageManager, operation: .inject,
            exactPackageManagedSHA256Match: true) == .skipExternalDuplicate {
            return "Decision: SKIP — identical SHA-256 is already owned by a package manager. FilterKit must not inject, copy, overwrite, export, uninstall, or adopt it."
        }
        return "Source check: no exact package-managed SHA-256 duplicate found in the current snapshot. Helper ownership and identity attestation is still required before any operation."
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
    @State private var showingReconcileConfirmation = false
    @State private var showingOperationNotice = false

    private var snapshotRevision: UInt64 { registry.snapshotRevision }
    private var operationBelongsToRow: Bool {
        (operationStore.pending?.command.pluginID == UUID(uuidString: plugin.filterKitPluginID ?? "") &&
         HelperBundleIdentifierKey.make(operationStore.pending?.command.targetBundleIdentifier ?? "")
            == HelperBundleIdentifierKey.make(app.bundleIdentifier)) ||
        operationStore.outcomeBelongs(pluginID: UUID(uuidString: plugin.filterKitPluginID ?? ""),
            targetBundleIdentifier: app.bundleIdentifier)
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
                            if operationStore.phase == .outcomeUnknown,
                               operationStore.outcomeResolution == .desiredStateObserved ||
                               operationStore.outcomeResolution == .previousStateObserved {
                                Button("common.ok") { operationStore.dismissScanObservation() }
                                    .font(.caption2)
                            }
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
                .disabled(!activation.canPreviewToggle || operationStore.phase == .preparing ||
                          operationStore.phase == .committing || operationStore.phase == .reconciling ||
                          operationStore.phase == .outcomeUnknown || operationStore.phase == .reconciledCommitted ||
                          operationStore.phase == .reconciledRolledBack)
                .accessibilityIdentifier("apps.detail.activation.toggle.\(plugin.id).\(app.bundleIdentifier)")
                .accessibilityLabel(Text("\(plugin.baseName) — \(app.displayName)"))
            if operationBelongsToRow && operationStore.phase == .outcomeUnknown {
                Button("apps.detail.activation_verify_helper") {
                    showingReconcileConfirmation = true
                }
                .font(.caption2)
                .accessibilityIdentifier("apps.detail.activation.reconcile.\(plugin.id).\(app.bundleIdentifier)")
            }
            if operationBelongsToRow && (operationStore.phase == .reconciledCommitted ||
                                          operationStore.phase == .reconciledRolledBack) {
                Button("common.ok") { operationStore.clearReconciledOutcome() }
                    .font(.caption2)
            }
        }
        .padding(.vertical, 3)
        .onChange(of: snapshotRevision) { _ in
            if operationStore.phase == .outcomeUnknown {
                operationStore.reconcileUnknownOutcome(using: activation)
            } else {
                operationStore.invalidatePending()
            }
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
        .confirmationDialog("apps.detail.activation_reconcile_title", isPresented: $showingReconcileConfirmation,
                            titleVisibility: .visible) {
            Button("apps.detail.activation_reconcile_confirm", role: .destructive) {
                Task {
                    await operationStore.reconcileWithHelper(userConfirmed: true)
                    showingOperationNotice = true
                }
            }
            Button("common.ok", role: .cancel) { }
        } message: {
            Text("apps.detail.activation_reconcile_message")
        }
        .alert("apps.detail.activation_operation_title", isPresented: $showingOperationNotice) {
            Button("common.ok", role: .cancel) { operationStore.clearReconciledOutcome() }
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
        case .reconciling: return "apps.detail.activation_reconciling"
        case .reconciledCommitted: return "apps.detail.activation_helper_committed"
        case .reconciledRolledBack: return "apps.detail.activation_helper_rolled_back"
        case .blocked: return "apps.detail.activation_operation_release_closed"
        case .outcomeUnknown:
            switch operationStore.outcomeResolution {
            case .desiredStateObserved: return "apps.detail.activation_outcome_desired_observed"
            case .previousStateObserved: return "apps.detail.activation_outcome_previous_observed"
            case .stillIndeterminate, .none: return "apps.detail.activation_operation_unknown"
            }
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
