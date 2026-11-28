import SwiftUI
import UIKit
import Combine
import UniformTypeIdentifiers

@MainActor
private final class PluginsViewModel: ObservableObject {
    /// Shared inventory registry: holds the most recent snapshot and runs the
    /// background scan. The view observes this registry directly.
    let registry = PluginScanRegistry.shared
    @Published private(set) var errorKey: String?
    @Published var backupShareItem: ShareableBackup?
    @Published var backupErrorKey: String?
    @Published var restoreErrorKey: String?
    @Published var restoreReview: BackupRestoreReview?
    @Published var restoreNoticeKey: String?
    @Published private(set) var appNamesByBundleID: [String: String] = [:]
    @Published private(set) var appNamesByExecutable: [String: String] = [:]
    private var appInventoryCancellable: AnyCancellable?

    private let appDiscovery = AppDiscoveryProviderRegistry.shared

    init() {
        AppDiscoveryProviderRegistry.startObservingSystemChanges()
        appInventoryCancellable = NotificationCenter.default
            .publisher(for: .filterKitAppInventoryDidRefresh)
            .compactMap { $0.object as? [InstalledApp] }
            .sink { [weak self] apps in
                Task { @MainActor [weak self] in
                    self?.applyAppNames(apps)
                }
            }
    }

    func exportAllManageable() {
        guard let result = registry.result else { backupErrorKey = "backup.export.scan_required"; return }
        let ids = result.plugins.compactMap { item -> UUID? in
            guard item.managementPermission?.canModify == true,
                  item.ownership == .filterKit,
                  let raw = item.filterKitPluginID else { return nil }
            return UUID(uuidString: raw)
        }
        guard !ids.isEmpty else { backupErrorKey = "backup.export.no_manageable_plugins"; return }
        do {
            let data = try FilterKitBackupService().makeBackup(scan: result, pluginIDs: ids)
            let name = "FilterKit-\(Int(Date().timeIntervalSince1970)).filterkitbackup"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try data.write(to: url, options: .atomic)
            backupShareItem = ShareableBackup(url: url)
            backupErrorKey = nil
        } catch {
            backupErrorKey = "backup.export.failed"
        }
    }

    func inspectBackupFile(_ url: URL) async {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            let service = FilterKitBackupService()
            let inspected = try service.inspectBackup(at: url)
            let installedApps = try await appDiscovery.scanInstalledApps()
            let installedIDs = Set(installedApps.map(\.bundleIdentifier))
            let currentScan = registry.result
            let existingNames: Set<String>
            let conflictingIDs: Set<UUID>
            let packageManagedHashes: Set<String>
            if let currentScan, currentScan.directoryState == .resolved {
                let directories = currentScan.scannedDirectories ?? currentScan.scannedDirectory.map { [$0] } ?? []
                let names = directories.flatMap { (try? FileManager.default.contentsOfDirectory(atPath: $0)) ?? [] }
                existingNames = Set(names)
                conflictingIDs = Set(currentScan.plugins.compactMap { item in
                    guard item.helperIdentityAttestation?.isVerified == true,
                          let raw = item.filterKitPluginID else { return nil }
                    return UUID(uuidString: raw)
                })
                packageManagedHashes = Set(currentScan.plugins.compactMap { item in
                    guard item.ownership == .packageManager else { return nil }
                    return item.dylibSHA256?.lowercased()
                })
            } else {
                existingNames = []
                conflictingIDs = []
                packageManagedHashes = []
            }
            let preview = BackupRestorePreviewBuilder().build(validated: inspected.plugins,
                installedBundleIdentifiers: installedIDs, existingFileNames: existingNames,
                conflictingPluginIDs: conflictingIDs,
                packageManagedDylibSHA256s: packageManagedHashes,
                filterToInstalledApps: UserDefaults.standard.object(
                    forKey: "filterkit.restore.onlyInstalledAssociatedApps") as? Bool ?? true)
            restoreReview = BackupRestoreReview(fileName: url.lastPathComponent,
                destinationInventoryAvailable: currentScan?.directoryState == .resolved,
                document: inspected.document, validatedPlugins: inspected.plugins, preview: preview)
            restoreErrorKey = nil
        } catch {
            restoreErrorKey = "backup.restore.inspect_failed"
        }
    }

    func confirmRestoreSelection(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { restoreErrorKey = "backup.restore.none_selected"; return }
        // P1-18 deliberately ends at an explicit, read-only confirmation. No files are deployed.
        restoreNoticeKey = "backup.restore.confirmed_read_only"
    }

    func load() async {
        // Initial entry reuses the shared snapshot and never forces a duplicate scan.
        registry.loadIfNeeded()
        // App display-name enrichment is a background complement: it must not hold
        // the plugin list's first paint. Snapshot names fill in immediately when
        // available; the refreshed inventory back-fills the dictionaries later.
        enrichAppNames()
    }

    /// Explicit user refresh: refresh the one shared PluginScanRegistry snapshot.
    /// List and detail observe that same registry; no page-local scanner is created.
    func refresh() {
        registry.refresh()
        enrichAppNames()
    }

    private func enrichAppNames() {
        guard registry.result != nil else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let snapshot = await self.appDiscovery.currentSnapshot()
            if let snapshot { self.applyAppNames(snapshot) }
            do {
                let apps = try await self.appDiscovery.scanInstalledApps()
                self.applyAppNames(apps)
            } catch {
                // Keep any snapshot-derived names; only clear when there was no snapshot.
                if snapshot == nil {
                    self.appNamesByBundleID = [:]
                    self.appNamesByExecutable = [:]
                }
            }
        }
    }

    private func applyAppNames(_ apps: [InstalledApp]) {
        let index = PluginAppDisplayIndex(apps: apps)
        appNamesByBundleID = index.namesByBundleIdentifier
        appNamesByExecutable = index.namesByExecutable
    }
}

struct PluginsView: View {
    @StateObject private var model = PluginsViewModel()
    @ObservedObject private var registry = PluginScanRegistry.shared
    @State private var showingFilterKitAssociatedOnly = false
    @State private var searchText = ""
    @State private var isImportingBackup = false

    private var visiblePlugins: [PluginScanItem] {
        let items = registry.result?.plugins ?? []
        return items.filter { item in
            // The Plugins page is an inventory of complete dylib + Filter.plist pairs.
            // Orphan/invalid scan records remain in the diagnostic scan result, but are
            // intentionally not presented as manageable plugins here.
            guard item.pairingState == .paired,
                  item.dylibFileName != nil, item.plistFileName != nil else { return false }
            let scopeMatches = PluginListScope.includes(item, filterKitAssociatedOnly: showingFilterKitAssociatedOnly)
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let searchMatches = query.isEmpty || item.baseName.localizedCaseInsensitiveContains(query)
                || (item.dylibFileName?.localizedCaseInsensitiveContains(query) ?? false)
                || (item.packageIdentifier?.localizedCaseInsensitiveContains(query) ?? false)
            return scopeMatches && searchMatches
        }.sorted { $0.baseName.localizedStandardCompare($1.baseName) == .orderedAscending }
    }

    var body: some View {
        NavigationView {
            Group {
                if let error = model.errorKey, registry.result == nil {
                    FKStateView(kind: .error, systemImage: "exclamationmark.triangle",
                                title: "plugins.error.title", message: LocalizedStringKey(error),
                                actionTitle: "plugins.refresh") {
                        Task { model.refresh() }
                    }
                } else if let result = registry.result, result.directoryState != .resolved {
                    FKStateView(kind: .empty, systemImage: "folder.badge.questionmark",
                                title: "plugins.directory_unavailable.title",
                                message: result.directoryState == .ambiguous
                                    ? "plugins.directory_ambiguous.message" : "plugins.directory_unavailable.message",
                                actionTitle: "plugins.refresh") {
                        Task { model.refresh() }
                    }
                } else if registry.isLoading && registry.result == nil {
                    // First scan: list frame renders first with an inline progress
                    // row instead of a full-screen loading transition.
                    List {
                        Section {
                            HStack(spacing: 12) {
                                ProgressView()
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("plugins.loading.title").font(.headline)
                                    Text("plugins.loading.message").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .refreshable { model.refresh() }
                } else if visiblePlugins.isEmpty {
                    FKStateView(kind: .empty, systemImage: "puzzlepiece",
                                title: searchText.isEmpty ? "plugins.empty.title" : "plugins.empty.search_title",
                                message: searchText.isEmpty ? "plugins.empty.message" : "plugins.empty.search_message",
                                actionTitle: "plugins.refresh") {
                        Task { model.refresh() }
                    }
                } else {
                    List {
                        if let result = registry.result {
                            Section {
                                HStack {
                                    Label("plugins.scan.read_only", systemImage: "lock.shield")
                                    Spacer()
                                    Text("\(result.plugins.count)")
                                        .foregroundStyle(.secondary)
                                }
                                let paths = result.scannedDirectories ?? result.scannedDirectory.map { [$0] } ?? []
                                if !paths.isEmpty {
                                    Text(paths.joined(separator: "\n")).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
                                }
                            }
                            if !result.identityConflicts.isEmpty {
                                Section("plugins.identity.global_conflicts") {
                                    ForEach(result.identityConflicts) { conflict in
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(conflict.kind.rawValue).font(.subheadline.weight(.medium))
                                            Text(conflict.pluginIDs.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                        Section {
                            ForEach(visiblePlugins) { plugin in
                                NavigationLink(destination: PluginScanDetailView(plugin: plugin, appNamesByBundleID: model.appNamesByBundleID)) {
                                    PluginScanRow(plugin: plugin, appNamesByBundleID: model.appNamesByBundleID)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .refreshable { model.refresh() }
                }
            }
            .navigationTitle("tab.plugins")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        Button { model.exportAllManageable() } label: {
                            Label("backup.export.manageable", systemImage: "square.and.arrow.up")
                        }
                        Button { isImportingBackup = true } label: {
                            Label("backup.restore.import", systemImage: "doc.badge.arrow.up")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("backup.actions")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showingFilterKitAssociatedOnly.toggle() } label: {
                        Image(systemName: showingFilterKitAssociatedOnly ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel(showingFilterKitAssociatedOnly ? "plugins.scope.filterkit_associated" : "plugins.scope.all")
                    .accessibilityValue(showingFilterKitAssociatedOnly ? "plugins.scope.filterkit_associated" : "plugins.scope.all")
                    .accessibilityIdentifier("plugins.scope.toggle")
                }
            }
            .searchable(text: $searchText, prompt: "plugins.search.prompt")
            .task { await model.load() }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .sheet(item: $model.backupShareItem) { item in
            BackupActivityView(activityItems: [item.url])
        }
        .sheet(item: $model.restoreReview) { review in
            BackupRestoreReviewView(review: review) { selectedIDs in
                model.confirmRestoreSelection(selectedIDs)
            }
        }
        .fileImporter(isPresented: $isImportingBackup,
                      allowedContentTypes: [UTType(filenameExtension: "filterkitbackup", conformingTo: .data) ?? .data],
                      allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task { await model.inspectBackupFile(url) }
            case .failure:
                model.restoreErrorKey = "backup.restore.import_failed"
            }
        }
        .alert("backup.export.title", isPresented: Binding(get: { model.backupErrorKey != nil }, set: { if !$0 { model.backupErrorKey = nil } })) {
            Button("common.ok", role: .cancel) { model.backupErrorKey = nil }
        } message: {
            Text(LocalizedStringKey(model.backupErrorKey ?? "backup.export.failed"))
        }
        .alert("backup.restore.title", isPresented: Binding(get: { model.restoreErrorKey != nil }, set: { if !$0 { model.restoreErrorKey = nil } })) {
            Button("common.ok", role: .cancel) { model.restoreErrorKey = nil }
        } message: {
            Text(LocalizedStringKey(model.restoreErrorKey ?? "backup.restore.inspect_failed"))
        }
        .alert("backup.restore.title", isPresented: Binding(get: { model.restoreNoticeKey != nil }, set: { if !$0 { model.restoreNoticeKey = nil } })) {
            Button("common.ok", role: .cancel) { model.restoreNoticeKey = nil }
        } message: {
            Text(LocalizedStringKey(model.restoreNoticeKey ?? "backup.restore.confirmed_read_only"))
        }
    }


}

private struct BackupRestoreReview: Identifiable {
    let id = UUID()
    let fileName: String
    let destinationInventoryAvailable: Bool
    let document: FilterKitBackupDocument
    let validatedPlugins: [ValidatedBackupPlugin]
    let preview: BackupRestorePreview
}

private struct BackupRestoreReviewView: View {
    let review: BackupRestoreReview
    let onConfirm: (Set<UUID>) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIDs: Set<UUID> = []
    @State private var showConfirmation = false

    private var selectableIDs: Set<UUID> {
        BackupRestoreSelectionPolicy.selectablePluginIDs(in: review.preview)
    }

    var body: some View {
        NavigationView {
            List {
                Section {
                    Text(review.fileName).font(.headline)
                    HStack {
                        Label("backup.restore.total", systemImage: "shippingbox")
                        Spacer()
                        Text("\(review.preview.plugins.count)")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Label("backup.restore.selectable", systemImage: "checkmark.circle")
                        Spacer()
                        Text("\(selectableIDs.count)").foregroundStyle(.secondary)
                    }
                    HStack {
                        Label("backup.restore.skipped", systemImage: "arrowshape.turn.up.right")
                        Spacer()
                        Text("\(review.preview.skippedCount)").foregroundStyle(.secondary)
                    }
                }
                if !review.destinationInventoryAvailable {
                    Section {
                        Label("backup.restore.destination_unavailable", systemImage: "exclamationmark.triangle")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section("backup.restore.plugins") {
                    ForEach(review.preview.plugins, id: \.pluginIdentifier) { item in
                        let entry = review.validatedPlugins.first { $0.entry.pluginIdentifier == item.pluginIdentifier }?.entry
                        HStack(alignment: .top, spacing: 10) {
                            Button { toggle(item.pluginIdentifier) } label: {
                                Image(systemName: selectedIDs.contains(item.pluginIdentifier) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                            }
                            .disabled(!selectableIDs.contains(item.pluginIdentifier))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry?.dylibFileName ?? item.pluginIdentifier.uuidString)
                                    .font(.body.weight(.medium))
                                Text(dispositionKey(item.disposition))
                                    .font(.caption).foregroundStyle(.secondary)
                                if let entry = entry {
                                    if let owner = entry.hardBoundBundleIdentifier {
                                        Text("\(NSLocalizedString("backup.restore.source_app", comment: "")): \(owner)")
                                            .font(.caption2).foregroundStyle(.secondary)
                                    } else {
                                        Text(NSLocalizedString("binding.additional_association_only", comment: ""))
                                            .font(.caption2).foregroundStyle(.secondary)
                                    }
                                    if !entry.softAssociatedBundleIdentifiers.isEmpty {
                                        Text(entry.softAssociatedBundleIdentifiers.joined(separator: ", "))
                                            .font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                if !item.missingBundleIdentifiers.isEmpty {
                                    Text(item.missingBundleIdentifiers.joined(separator: ", "))
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                if !item.conflictingFileNames.isEmpty {
                                    Text(item.conflictingFileNames.joined(separator: ", "))
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 3)
                    }
                }
                Section {
                    Label("backup.restore.read_only_notice", systemImage: "lock.shield")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("backup.restore.review_title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("backup.restore.confirm_selection") { showConfirmation = true }
                        .disabled(selectedIDs.isEmpty)
                }
            }
            .confirmationDialog("backup.restore.confirm_title", isPresented: $showConfirmation, titleVisibility: .visible) {
                Button("backup.restore.confirm_selection", role: .destructive) {
                    onConfirm(selectedIDs)
                    dismiss()
                }
                Button("common.cancel", role: .cancel) {}
            } message: {
                Text("backup.restore.confirm_message")
            }
        }
    }

    private func toggle(_ id: UUID) {
        if selectedIDs.contains(id) { selectedIDs.remove(id) } else if selectableIDs.contains(id) { selectedIDs.insert(id) }
    }

    private func dispositionKey(_ disposition: BackupRestoreDisposition) -> LocalizedStringKey {
        switch disposition {
        case .ready: return "backup.restore.status.ready"
        case .hardBoundAppMissing: return "backup.restore.status.hard_app_missing"
        case .softAppsMissing: return "backup.restore.status.soft_apps_missing"
        case .fileConflict: return "backup.restore.status.file_conflict"
        case .identityConflict: return "backup.restore.status.identity_conflict"
        case .skippedNoInstalledAssociation: return "backup.restore.status.no_installed_association"
        case .externalDuplicate: return "backup.restore.status.external_duplicate"
        }
    }
}

private struct ShareableBackup: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

private struct BackupActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

private struct PluginScanRow: View {
    let plugin: PluginScanItem
    let appNamesByBundleID: [String: String]
    private var associationStatusText: String {
        let status = PluginListStatus(item: plugin)
        guard !status.apps.isEmpty else { return NSLocalizedString("plugins.row.association_none", comment: "") }

        // The Fixed Owner App is always the first/default association shown.
        // Keep the row compact: at most two names, then a remaining-count suffix.
        let visible = Array(status.apps.prefix(2))
        let names = visible.map { appNamesByBundleID[$0.bundleIdentifier.lowercased()] ?? $0.bundleIdentifier }
        let remainder = max(0, status.apps.count - visible.count)
        let summary = remainder > 0
            ? String(format: NSLocalizedString("plugins.row.more_apps", comment: ""), remainder)
            : ""
        let joined = names.joined(separator: "、")
        return String(format: NSLocalizedString("plugins.row.associated_apps", comment: ""), joined + summary)
    }

    private var managementAndInjectionText: String {
        let status = PluginListStatus(item: plugin)
        let managementKey = status.managementType == .appAssociated
            ? "plugins.row.management_app_associated"
            : "plugins.row.management_standalone"
        let management = NSLocalizedString(managementKey, comment: "")
        guard !status.apps.isEmpty else { return management }

        let injection: String
        if status.unknownCount > 0 {
            injection = String(format: NSLocalizedString("plugins.row.injection_counts", comment: ""),
                status.enabledCount, status.disabledCount, status.unknownCount)
        } else if status.enabledCount == status.apps.count {
            injection = NSLocalizedString("plugins.row.injection_all_enabled", comment: "")
        } else if status.disabledCount == status.apps.count {
            injection = NSLocalizedString("plugins.row.injection_all_disabled", comment: "")
        } else {
            injection = String(format: NSLocalizedString("plugins.row.injection_counts", comment: ""),
                status.enabledCount, status.disabledCount, status.unknownCount)
        }
        return "\(management) · \(injection)"
    }

    private var sourceText: String {
        if plugin.ownership == .filterKit {
            return NSLocalizedString("plugins.row.source_filterkit", comment: "")
        }
        if plugin.ownership == .unknown {
            return NSLocalizedString("plugins.row.source_unknown", comment: "")
        }
        switch plugin.ownership {
        case .filterKit: return NSLocalizedString("plugins.row.source_filterkit", comment: "")
        case .packageManager: return NSLocalizedString("plugins.row.source_package_manager", comment: "")
        case .unknown: return NSLocalizedString("plugins.row.source_unknown", comment: "")
        }
    }


    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "puzzlepiece.extension.fill")
                .font(.title2).foregroundStyle(.secondary).frame(width: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(plugin.baseName).font(.body.weight(.medium))
                if let fileName = plugin.dylibFileName {
                    Text(fileName).font(.caption).foregroundStyle(.secondary)
                }
                Text(associationStatusText)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text(managementAndInjectionText)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text(sourceText)
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if plugin.ownership == .filterKit {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
            } else if plugin.ownership == .packageManager {
                Image(systemName: "shippingbox.fill").foregroundStyle(.secondary)
            } else {
                Image(systemName: "questionmark.circle").foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct PluginSoftAssociationManagerSection: View {
    let plugin: PluginScanItem

    @State private var apps: [InstalledApp] = []
    @State private var draft: PluginAssociationPlan?
    @State private var original: PluginAssociationPlan?
    @State private var isLoading = false
    @State private var loadErrorKey: String?
    @State private var reviewMessage = ""
    @State private var showingReview = false
    @State private var showingSaveConfirmation = false
    @State private var isSaving = false
    @State private var saveResultKey: String?

    private let appDiscovery = AppDiscoveryProviderRegistry.shared
    private let editor = PluginAssociationPlanEditor()

    private var isManageable: Bool {
        plugin.ownership == .filterKit
            && plugin.managementPermission?.canModify == true
            && plugin.pairingState == .paired
            && plugin.ownershipConflict == .none
            && plugin.identityConflictIDs.isEmpty
            && UUID(uuidString: plugin.filterKitPluginID ?? "") != nil
            && plugin.hardBoundBundleIdentifier.map(PluginAssociationPlanResolver.isValidBundleIdentifier) == true
    }

    private var installedBundleIDs: Set<String> { HelperBundleIdentifierKey.set(apps.map(\.bundleIdentifier)) }
    private var hardBoundID: String? { plugin.hardBoundBundleIdentifier }
    private var selectableApps: [InstalledApp] {
        apps.filter { HelperBundleIdentifierKey.make($0.bundleIdentifier) != HelperBundleIdentifierKey.make(hardBoundID ?? "") }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }
    private var associatedIDs: Set<String> { HelperBundleIdentifierKey.set(draft?.softAssociations.map(\.bundleIdentifier) ?? []) }
    private var missingAssociatedIDs: [String] {
        (draft?.softAssociations.map(\.bundleIdentifier) ?? []).filter { !installedBundleIDs.contains(HelperBundleIdentifierKey.make($0)) }.sorted()
    }
    private var hasChanges: Bool { draft != nil && original != nil && draft != original }

    var body: some View {
        Section("plugins.association_manager.title") {
            if let hardBoundID {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("plugins.association_manager.hard_bound")
                        Text(hardBoundID).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        Text(apps.contains(where: { HelperBundleIdentifierKey.make($0.bundleIdentifier) == HelperBundleIdentifierKey.make(hardBoundID) })
                             ? "plugins.association_manager.app_available"
                             : "plugins.association_manager.app_unavailable_preserved")
                            .font(.caption2)
                            .foregroundStyle(apps.contains(where: { HelperBundleIdentifierKey.make($0.bundleIdentifier) == HelperBundleIdentifierKey.make(hardBoundID) }) ? .green : .orange)
                    }
                } icon: {
                    Image(systemName: "lock.shield")
                }
            } else {
                Label("plugins.association_manager.hard_bound_missing", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }

            if !isManageable {
                Label("plugins.association_manager.read_only", systemImage: "lock.fill")
                    .font(.footnote).foregroundStyle(.secondary)
            } else if isLoading && draft == nil {
                HStack { ProgressView(); Text("plugins.association_manager.loading").font(.footnote).foregroundStyle(.secondary) }
            } else if let loadErrorKey {
                Label(LocalizedStringKey(loadErrorKey), systemImage: "exclamationmark.triangle")
                    .font(.footnote).foregroundStyle(.orange)
            } else if let draft {
                Text("plugins.association_manager.instructions")
                    .font(.footnote).foregroundStyle(.secondary)
                Label("plugins.association_manager.activation_from_app", systemImage: "arrow.left.arrow.right")
                    .font(.caption).foregroundStyle(.secondary)

                if selectableApps.isEmpty {
                    Text("plugins.association_manager.no_apps")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    ForEach(selectableApps) { app in
                        // This checkmark edits only Additional App Association membership.
                        // It is not an injection enable/disable control.
                        Button {
                            toggleAssociation(for: app)
                        } label: {
                            HStack(spacing: 10) {
                                if associatedIDs.contains(HelperBundleIdentifierKey.make(app.bundleIdentifier)) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.title3).foregroundColor(FilterKitTheme.ColorToken.accent)
                                } else {
                                    Image(systemName: "circle")
                                        .font(.title3).foregroundColor(.secondary)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(app.displayName).foregroundStyle(.primary)
                                    Text(app.bundleIdentifier).font(.caption).foregroundStyle(.secondary)
                                    if app.systemClassification == .system {
                                        Text("apps.badge.system").font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if associatedIDs.contains(HelperBundleIdentifierKey.make(app.bundleIdentifier)) {
                                    Text("plugins.association_manager.associated")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("plugins.association.toggle.\(app.bundleIdentifier)")
                        .accessibilityValue(associatedIDs.contains(HelperBundleIdentifierKey.make(app.bundleIdentifier)) ? "associated" : "not associated")
                    }
                }

                if !missingAssociatedIDs.isEmpty {
                    ForEach(missingAssociatedIDs, id: \.self) { bundleID in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(bundleID).font(.caption).textSelection(.enabled)
                                Text("plugins.association_manager.missing_app").font(.caption2).foregroundStyle(.orange)
                            }
                            Spacer()
                            Button("plugins.association_manager.remove") { removeAssociation(bundleID) }
                                .font(.caption)
                        }
                    }
                }

                HStack {
                    Text("plugins.association_manager.selected_count")
                    Spacer()
                    Text("\(draft.softAssociations.count)").foregroundStyle(.secondary)
                }
                .font(.footnote)

                Button {
                    reviewMessage = makeReviewMessage()
                    showingReview = true
                } label: {
                    Label("plugins.association_manager.review_changes", systemImage: "doc.text.magnifyingglass")
                }
                .disabled(!hasChanges)
                .accessibilityIdentifier("plugins.association.review_changes")

                Button {
                    showingSaveConfirmation = true
                } label: {
                    if isSaving { ProgressView() } else { Label("plugins.association_manager.save", systemImage: "checkmark.circle") }
                }
                .disabled(!hasChanges || isSaving)
                .accessibilityIdentifier("plugins.association.save")
                if let saveResultKey {
                    Label(LocalizedStringKey(saveResultKey), systemImage: "info.circle")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Label("plugins.association_manager.not_saved", systemImage: "lock.shield")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("plugins.association_manager.unavailable")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .task { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .filterKitAppInventoryDidRefresh)) { notification in
            guard let refreshedApps = notification.object as? [InstalledApp] else { return }
            // Bundle-ID membership alone changes availability. Keep the draft and
            // every per-App enabled bit untouched across uninstall/reinstall.
            apps = refreshedApps
        }
        .alert("plugins.association_manager.review_title", isPresented: $showingReview) {
            Button("common.ok", role: .cancel) { }
        } message: { Text(reviewMessage) }
        .confirmationDialog("plugins.association_manager.confirm_save", isPresented: $showingSaveConfirmation, titleVisibility: .visible) {
            Button("plugins.association_manager.confirm_save_action", role: .destructive) { Task { await save() } }
            Button("common.cancel", role: .cancel) { }
        } message: { Text("plugins.association_manager.confirm_save_message") }
    }

    @MainActor
    private func load() async {
        guard !isLoading, draft == nil else { return }
        guard isManageable,
              let pluginID = UUID(uuidString: plugin.filterKitPluginID ?? ""),
              let hardBoundID else {
            loadErrorKey = "plugins.association_manager.not_editable"
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let discovered = try await appDiscovery.scanInstalledApps()
            apps = discovered
            // Preserve schema-3 enabled bits. Legacy schema-1/2 associations retain
            // their established compatibility interpretation (enabled) until migrated.
            let states = plugin.softAssociationStates ?? plugin.softAssociatedBundleIdentifiers.map {
                FilterKitManifestSoftAssociation(bundleIdentifier: $0, isEnabled: true)
            }
            let plan = PluginAssociationPlan(pluginID: pluginID, hardBoundBundleIdentifier: hardBoundID,
                softAssociations: states.map { PluginSoftAssociation(bundleIdentifier: $0.bundleIdentifier, isEnabled: $0.isEnabled) })
            draft = plan
            original = plan
            loadErrorKey = nil
        } catch {
            loadErrorKey = "plugins.association_manager.apps_unavailable"
        }
    }

    private func toggleAssociation(for app: InstalledApp) {
        guard let current = draft else { return }
        let appKey = HelperBundleIdentifierKey.make(app.bundleIdentifier)
        if associatedIDs.contains(appKey) {
            apply(.removeSoft(bundleIdentifier: app.bundleIdentifier), to: current)
        } else if let prior = original?.softAssociations.first(where: { HelperBundleIdentifierKey.make($0.bundleIdentifier) == appKey }) {
            apply(.restoreSoft(association: prior), to: current)
        } else {
            apply(.addSoft(bundleIdentifier: app.bundleIdentifier), to: current)
        }
    }

    private func removeAssociation(_ bundleID: String) {
        guard let current = draft else { return }
        apply(.removeSoft(bundleIdentifier: bundleID), to: current)
    }

    private func apply(_ edit: PluginAssociationEdit, to plan: PluginAssociationPlan) {
        switch editor.applying(edit, to: plan, installedBundleIdentifiers: installedBundleIDs, pluginIsManageable: isManageable) {
        case .success(let updated): draft = updated
        case .failure: loadErrorKey = "plugins.association_manager.edit_rejected"
        }
    }


    @MainActor
    private func save() async {
        guard let draft, let baseline = original, let hardBoundID,
              let pluginID = UUID(uuidString: plugin.filterKitPluginID ?? ""), draft != baseline else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let service = try HelperPluginAssociationCommitService.production()
            let receipt = try await service.replaceSoftAssociations(plugin: plugin,
                hardBoundBundleIdentifier: hardBoundID, desired: draft.softAssociations, userConfirmed: true)
            // The Helper receipt is the commit boundary. Refresh the one shared inventory
            // only after a validated receipt so list/detail never treat a local draft as
            // authoritative disk state. Plugin page still does not own per-App activation.
            guard receipt.pluginID == pluginID,
                  receipt.action == .replaceSoftAssociations else {
                throw HelperDeploymentCoordinator.CoordinatorError.invalidReceipt
            }
            original = draft
            RuntimeEventLogger.recordPluginOperation("association", outcome: .completed,
                pluginID: pluginID.uuidString, traceID: receipt.requestID.uuidString)
            PluginScanRegistry.shared.refresh()
            saveResultKey = "plugins.association_manager.save_success"
        } catch {
            RuntimeEventLogger.recordPluginOperation("association", outcome: .failed,
                pluginID: pluginID.uuidString)
            saveResultKey = "plugins.association_manager.save_blocked"
        }
    }

    private func makeReviewMessage() -> String {
        guard let draft, let original else { return NSLocalizedString("plugins.association_manager.no_changes", comment: "") }
        let old = HelperBundleIdentifierKey.set(original.softAssociations.map(\.bundleIdentifier))
        let new = HelperBundleIdentifierKey.set(draft.softAssociations.map(\.bundleIdentifier))
        let added = new.subtracting(old).sorted()
        let removed = old.subtracting(new).sorted()
        var lines: [String] = []
        if !added.isEmpty { lines.append(NSLocalizedString("plugins.association_manager.added", comment: "") + ": " + added.joined(separator: ", ")) }
        if !removed.isEmpty { lines.append(NSLocalizedString("plugins.association_manager.removed", comment: "") + ": " + removed.joined(separator: ", ")) }
        if lines.isEmpty { lines.append(NSLocalizedString("plugins.association_manager.no_changes", comment: "")) }
        lines.append(NSLocalizedString("plugins.association_manager.review_only", comment: ""))
        return lines.joined(separator: "\n")
    }
}

private struct PluginScanDetailView: View {
    let plugin: PluginScanItem
    let appNamesByBundleID: [String: String]
    @ObservedObject private var registry = PluginScanRegistry.shared

    private var displayedPlugin: PluginScanItem {
        registry.result?.plugins.first(where: { $0.id == plugin.id }) ?? plugin
    }

    var body: some View {
        List {
            Section("plugins.detail.identity") {
                detailRow("plugins.detail.name", displayedPlugin.baseName)
                if let dylib = displayedPlugin.dylibFileName { detailRow("dylib", dylib) }
                if let plist = displayedPlugin.plistFileName { detailRow("plist", plist) }
                detailRow("plugins.detail.ownership", ownershipText)
                detailRow("plugins.detail.permission", permissionText)
                if let package = displayedPlugin.packageIdentifier { detailRow("plugins.detail.package", package) }
                if let version = displayedPlugin.packageVersion { detailRow("plugins.detail.package_version", version) }
                detailRow("plugins.detail.binary", displayedPlugin.binaryKind?.rawValue ?? "unknown")
                detailRow("plugins.identity.status", displayedPlugin.identityStatus.rawValue)
                detailRow("plugins.identity.manifest_binding", displayedPlugin.manifestIdentityBinding.rawValue)
                if let fingerprint = displayedPlugin.identityFingerprint {
                    detailRow("plugins.identity.fingerprint", fingerprint)
                }
                if displayedPlugin.ownershipConflict != .none {
                    detailRow("plugins.ownership.conflict", displayedPlugin.ownershipConflict.rawValue)
                }
                if let owner = displayedPlugin.dylibPackageIdentifier {
                    detailRow("plugins.ownership.dylib_owner", owner)
                }
                if let owner = displayedPlugin.plistPackageIdentifier {
                    detailRow("plugins.ownership.plist_owner", owner)
                }
            }
            Section("plugins.detail.app_associations") {
                let status = PluginListStatus(item: displayedPlugin)
                detailRow("plugins.detail.management_type", NSLocalizedString(
                    status.managementType == .appAssociated ? "plugins.row.management_app_associated" : "plugins.row.management_standalone", comment: ""))
                if status.apps.isEmpty {
                    detailRow("plugins.detail.associated_apps", NSLocalizedString("plugins.row.association_none", comment: ""))
                } else {
                    ForEach(status.apps, id: \.bundleIdentifier) { app in
                        let name = appNamesByBundleID[app.bundleIdentifier.lowercased()] ?? app.bundleIdentifier
                        let stateKey: String
                        switch app.injection {
                        case .enabled: stateKey = "plugins.row.injection_enabled"
                        case .disabled: stateKey = "plugins.row.injection_disabled"
                        case .unknown: stateKey = "plugins.row.injection_unknown"
                        }
                        let titleKey = app.isFixedOwner ? "plugins.detail.fixed_owner_app" : "plugins.detail.associated_app"
                        detailRow(LocalizedStringKey(titleKey), "\(name) · \(NSLocalizedString(stateKey, comment: ""))")
                    }
                }
                detailRow("plugins.detail.source", sourceText)
            }
            if let filter = displayedPlugin.filterConfiguration {
                Section("plugins.detail.filter") {
                    detailRow("plugins.filter.container", filter.containerKey)
                    detailRow("plugins.filter.parse_state", filter.parseState.rawValue)
                    detailRow("plugins.filter.bundles", filter.bundles.isEmpty ? "—" : filter.bundles.joined(separator: ", "))
                    detailRow("plugins.filter.executables", filter.executables.isEmpty ? "—" : filter.executables.joined(separator: ", "))
                    detailRow("plugins.filter.classes", filter.classes.isEmpty ? "—" : filter.classes.joined(separator: ", "))
                    detailRow("plugins.filter.mode", filter.modeDescription ?? "—")
                    detailRow("plugins.filter.unknown_keys", filter.unknownKeys.isEmpty ? "—" : filter.unknownKeys.joined(separator: ", "))
                    ForEach(filter.warnings, id: \.self) { Text(LocalizedStringKey($0)).font(.caption).foregroundStyle(.secondary) }
                }
            }
            PluginSoftAssociationManagerSection(plugin: displayedPlugin)
            if !displayedPlugin.identityConflictIDs.isEmpty {
                Section("plugins.identity.conflicts") {
                    ForEach(displayedPlugin.identityConflictIDs, id: \.self) { Text($0).font(.caption).textSelection(.enabled) }
                }
            }
            Section("plugins.detail.macho") {
                if let value = displayedPlugin.machOInstallName { detailRow("plugins.macho.install_name", value) }
                if let value = displayedPlugin.machOCurrentVersion { detailRow("plugins.macho.current_version", value) }
                if let value = displayedPlugin.machOCompatibilityVersion { detailRow("plugins.macho.compatibility_version", value) }
                if !displayedPlugin.machOUUIDs.isEmpty {
                    detailRow("plugins.macho.uuid", displayedPlugin.machOUUIDs.joined(separator: ", "))
                } else if let value = displayedPlugin.machOUUID { detailRow("plugins.macho.uuid", value) }
                detailRow("plugins.macho.architectures", displayedPlugin.machOArchitectures.isEmpty ? "—" : displayedPlugin.machOArchitectures.joined(separator: ", "))
                detailRow("plugins.macho.cdhash", displayedPlugin.machOCDHashes.isEmpty ? "—" : displayedPlugin.machOCDHashes.joined(separator: ", "))
                detailRow("plugins.macho.signature_state", displayedPlugin.codeSignatureStates.isEmpty ? "—" : displayedPlugin.codeSignatureStates.joined(separator: ", "))
                ForEach(displayedPlugin.machOSliceDetails, id: \.self) { Text($0).font(.caption).textSelection(.enabled) }
            }
            Section("plugins.detail.integrity") {
                if let hash = displayedPlugin.dylibSHA256 { detailRow("SHA-256 dylib", hash).textSelection(.enabled) }
                if let hash = displayedPlugin.plistSHA256 { detailRow("SHA-256 plist", hash).textSelection(.enabled) }
                ForEach(displayedPlugin.warnings, id: \.self) { Text(LocalizedStringKey($0)).font(.caption).foregroundStyle(.secondary) }
            }
            Section("plugins.detail.management") {
                if displayedPlugin.ownership == .filterKit {
                    Button(role: .destructive) { } label: {
                        Label("plugins.uninstall.disabled", systemImage: "trash")
                    }
                    .disabled(true)
                    .accessibilityIdentifier("plugins.detail.uninstall.locked")
                    Text("plugins.uninstall.locked_message")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    Label("plugins.management.read_only", systemImage: "lock.fill")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section {
                Label("plugins.detail.read_only_notice", systemImage: "lock.shield")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(displayedPlugin.baseName)
        .navigationBarTitleDisplayMode(.inline)
    }
    @ViewBuilder
    private func detailRow(_ title: LocalizedStringKey, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
            Spacer(minLength: 12)
            Text(value).foregroundStyle(.secondary).multilineTextAlignment(.trailing).textSelection(.enabled)
        }
    }
    private var sourceText: String {
        switch displayedPlugin.ownership {
        case .filterKit: return NSLocalizedString("plugins.row.source_filterkit", comment: "")
        case .packageManager: return NSLocalizedString("plugins.row.source_package_manager", comment: "")
        case .unknown: return NSLocalizedString("plugins.row.source_unknown", comment: "")
        }
    }
    private var ownershipText: String {
        switch displayedPlugin.ownership {
        case .filterKit: return NSLocalizedString("plugins.ownership.filterkit", comment: "")
        case .packageManager: return NSLocalizedString("plugins.ownership.package_manager", comment: "")
        case .unknown: return NSLocalizedString("plugins.ownership.unknown", comment: "")
        }
    }
    private var permissionText: String {
        guard let permission = displayedPlugin.managementPermission else { return NSLocalizedString("plugins.permission.not_evaluated", comment: "") }
        return NSLocalizedString(permission.reasonKey, comment: "")
    }
}
