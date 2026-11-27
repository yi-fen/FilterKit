import SwiftUI
import UIKit
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

    private let appDiscovery = AppDiscoveryProviderRegistry.shared

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
            if let currentScan, currentScan.directoryState == .resolved {
                let directories = currentScan.scannedDirectories ?? currentScan.scannedDirectory.map { [$0] } ?? []
                let names = directories.flatMap { (try? FileManager.default.contentsOfDirectory(atPath: $0)) ?? [] }
                existingNames = Set(names)
                conflictingIDs = Set(currentScan.plugins.compactMap { item in
                    guard item.helperIdentityAttestation?.isVerified == true,
                          let raw = item.filterKitPluginID else { return nil }
                    return UUID(uuidString: raw)
                })
            } else {
                existingNames = []
                conflictingIDs = []
            }
            let preview = BackupRestorePreviewBuilder().build(validated: inspected.plugins,
                installedBundleIdentifiers: installedIDs, existingFileNames: existingNames,
                conflictingPluginIDs: conflictingIDs)
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
        // Background scan runs in the shared registry; the existing snapshot, if
        // any, stays visible while it runs. Environment probing is off the main
        // actor there, so this does not block the first frame.
        registry.loadIfNeeded()
        // App display-name enrichment is a background complement: it must not hold
        // the plugin list's first paint. Snapshot names fill in immediately when
        // available; the refreshed inventory back-fills the dictionaries later.
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
        appNamesByBundleID = Dictionary(apps.map { ($0.bundleIdentifier, $0.displayName) },
                                        uniquingKeysWith: { first, _ in first })
        appNamesByExecutable = Dictionary(apps.compactMap { app in
            app.executableName.map { ($0.lowercased(), app.displayName) }
        }, uniquingKeysWith: { first, _ in first })
    }
}

struct PluginsView: View {
    @StateObject private var model = PluginsViewModel()
    @State private var showingFilterKitOnly = false
    @State private var searchText = ""
    @State private var isImportingBackup = false

    private var visiblePlugins: [PluginScanItem] {
        let items = model.registry.result?.plugins ?? []
        return items.filter { item in
            let scopeMatches = PluginListScope.includes(item, filterKitOnly: showingFilterKitOnly)
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
                if let error = model.errorKey, model.registry.result == nil {
                    FKStateView(kind: .error, systemImage: "exclamationmark.triangle",
                                title: "plugins.error.title", message: LocalizedStringKey(error),
                                actionTitle: "plugins.refresh") {
                        Task { await model.load() }
                    }
                } else if let result = model.registry.result, result.directoryState != .resolved {
                    FKStateView(kind: .empty, systemImage: "folder.badge.questionmark",
                                title: "plugins.directory_unavailable.title",
                                message: result.directoryState == .ambiguous
                                    ? "plugins.directory_ambiguous.message" : "plugins.directory_unavailable.message",
                                actionTitle: "plugins.refresh") {
                        Task { await model.load() }
                    }
                } else if model.registry.isLoading && model.registry.result == nil {
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
                    .refreshable { await model.load() }
                } else if visiblePlugins.isEmpty {
                    FKStateView(kind: .empty, systemImage: "puzzlepiece",
                                title: searchText.isEmpty ? "plugins.empty.title" : "plugins.empty.search_title",
                                message: searchText.isEmpty ? "plugins.empty.message" : "plugins.empty.search_message",
                                actionTitle: "plugins.refresh") {
                        Task { await model.load() }
                    }
                } else {
                    List {
                        if let result = model.registry.result {
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
                                NavigationLink(destination: PluginScanDetailView(plugin: plugin)) {
                                    PluginScanRow(plugin: plugin, appNamesByBundleID: model.appNamesByBundleID, appNamesByExecutable: model.appNamesByExecutable)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .refreshable { await model.load() }
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
                    Button { showingFilterKitOnly.toggle() } label: {
                        Image(systemName: showingFilterKitOnly ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel(showingFilterKitOnly ? "plugins.scope.managed" : "plugins.scope.all")
                    .accessibilityValue(showingFilterKitOnly ? "plugins.scope.managed" : "plugins.scope.all")
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
                                    Text("\(NSLocalizedString("backup.restore.source_app", comment: "")): \(entry.hardBoundBundleIdentifier)")
                                        .font(.caption2).foregroundStyle(.secondary)
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
    let appNamesByExecutable: [String: String]

    private var fileAndPairingText: String {
        let fileName = plugin.dylibFileName ?? plugin.plistFileName ?? plugin.manifestFileName ?? plugin.id
        return "\(fileName)  \(pairingText)"
    }

    private var associationText: String {
        if let hardBound = plugin.hardBoundBundleIdentifier {
            let name = appNamesByBundleID[hardBound] ?? hardBound
            let softNames = plugin.softAssociatedBundleIdentifiers.map { appNamesByBundleID[$0] ?? $0 }
            let uniqueSoftNames = Array(Set(softNames)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            let hardBoundText = String(format: NSLocalizedString("plugins.row.hard_bound", comment: ""), name)
            guard !uniqueSoftNames.isEmpty else { return hardBoundText }
            return hardBoundText + " · " + String(format: NSLocalizedString("plugins.row.associated_apps", comment: ""), uniqueSoftNames.joined(separator: ", "))
        }
        guard let filter = plugin.filterConfiguration else {
            return NSLocalizedString("plugins.row.no_association", comment: "")
        }
        if filter.bundles.contains("*") {
            return NSLocalizedString("plugins.row.global_association", comment: "")
        }
        let bundleIDs = Set(filter.bundles)
        let executableIDs = Set(filter.executables.map { $0.lowercased() })
        let matchedBundles = bundleIDs.compactMap { appNamesByBundleID[$0] }
        let matchedExecutables = executableIDs.compactMap { appNamesByExecutable[$0] }
        let names = Array(Set(matchedBundles + matchedExecutables)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        if !names.isEmpty { return String(format: NSLocalizedString("plugins.row.associated_apps", comment: ""), names.joined(separator: ", ")) }
        if !executableIDs.isEmpty {
            return NSLocalizedString("plugins.row.executable_targets", comment: "")
        }
        return NSLocalizedString("plugins.row.no_association", comment: "")
    }

    private var sourceText: String {
        if plugin.ownership == .filterKit {
            return NSLocalizedString("plugins.row.source_filterkit", comment: "")
        }
        if plugin.manifestFileName != nil {
            return NSLocalizedString("plugins.row.filterkit_manifest_unverified", comment: "")
        }
        switch plugin.ownership {
        case .filterKit: return NSLocalizedString("plugins.row.source_filterkit", comment: "")
        case .packageManager: return NSLocalizedString("plugins.row.source_package_manager", comment: "")
        case .unknown: return NSLocalizedString("plugins.row.source_unknown", comment: "")
        }
    }

    private var pairingText: String {
        switch plugin.pairingState {
        case .paired: return NSLocalizedString("plugins.pairing.paired", comment: "")
        case .orphanDylib, .orphanPlist, .unreadable, .invalid:
            return NSLocalizedString("plugins.pairing.unpaired", comment: "")
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "puzzlepiece.extension.fill")
                .font(.title2).foregroundStyle(.secondary).frame(width: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(plugin.baseName).font(.body.weight(.medium))
                Text(fileAndPairingText).font(.caption).foregroundStyle(.secondary)
                Text("\(associationText) · \(sourceText)")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
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

    private var installedBundleIDs: Set<String> { Set(apps.map(\.bundleIdentifier)) }
    private var hardBoundID: String? { plugin.hardBoundBundleIdentifier }
    private var selectableApps: [InstalledApp] {
        apps.filter { $0.bundleIdentifier != hardBoundID }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }
    private var associatedIDs: Set<String> { Set(draft?.softAssociations.map(\.bundleIdentifier) ?? []) }
    private var missingAssociatedIDs: [String] {
        (draft?.softAssociations.map(\.bundleIdentifier) ?? []).filter { !installedBundleIDs.contains($0) }.sorted()
    }
    private var hasChanges: Bool { draft != nil && original != nil && draft != original }

    var body: some View {
        Section("plugins.association_manager.title") {
            if let hardBoundID {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("plugins.association_manager.hard_bound")
                        Text(hardBoundID).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
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
                        Button {
                            toggleAssociation(for: app)
                        } label: {
                            HStack(spacing: 10) {
                                if associatedIDs.contains(app.bundleIdentifier) {
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
                                if associatedIDs.contains(app.bundleIdentifier) {
                                    Text("plugins.association_manager.associated")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("plugins.association.toggle.\(app.bundleIdentifier)")
                        .accessibilityValue(associatedIDs.contains(app.bundleIdentifier) ? "associated" : "not associated")
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
        if associatedIDs.contains(app.bundleIdentifier) {
            apply(.removeSoft(bundleIdentifier: app.bundleIdentifier), to: current)
        } else if let prior = original?.softAssociations.first(where: { $0.bundleIdentifier == app.bundleIdentifier }) {
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
        guard let draft, let original, let hardBoundID, draft != original else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let service = try HelperPluginAssociationCommitService.production()
            _ = try await service.replaceSoftAssociations(plugin: plugin,
                hardBoundBundleIdentifier: hardBoundID, desired: draft.softAssociations, userConfirmed: true)
            original = draft
            saveResultKey = "plugins.association_manager.save_success"
        } catch {
            saveResultKey = "plugins.association_manager.save_blocked"
        }
    }

    private func makeReviewMessage() -> String {
        guard let draft, let original else { return NSLocalizedString("plugins.association_manager.no_changes", comment: "") }
        let old = Set(original.softAssociations.map(\.bundleIdentifier))
        let new = Set(draft.softAssociations.map(\.bundleIdentifier))
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
    var body: some View {
        List {
            Section("plugins.detail.identity") {
                detailRow("plugins.detail.name", plugin.baseName)
                if let dylib = plugin.dylibFileName { detailRow("dylib", dylib) }
                if let plist = plugin.plistFileName { detailRow("plist", plist) }
                detailRow("plugins.detail.ownership", ownershipText)
                detailRow("plugins.detail.permission", permissionText)
                if let package = plugin.packageIdentifier { detailRow("plugins.detail.package", package) }
                if let version = plugin.packageVersion { detailRow("plugins.detail.package_version", version) }
                detailRow("plugins.detail.pairing", pairingText)
                detailRow("plugins.detail.binary", plugin.binaryKind?.rawValue ?? "unknown")
                detailRow("plugins.identity.status", plugin.identityStatus.rawValue)
                detailRow("plugins.identity.manifest_binding", plugin.manifestIdentityBinding.rawValue)
                if let fingerprint = plugin.identityFingerprint {
                    detailRow("plugins.identity.fingerprint", fingerprint)
                }
                if plugin.ownershipConflict != .none {
                    detailRow("plugins.ownership.conflict", plugin.ownershipConflict.rawValue)
                }
                if let owner = plugin.dylibPackageIdentifier {
                    detailRow("plugins.ownership.dylib_owner", owner)
                }
                if let owner = plugin.plistPackageIdentifier {
                    detailRow("plugins.ownership.plist_owner", owner)
                }
            }
            if let filter = plugin.filterConfiguration {
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
            PluginSoftAssociationManagerSection(plugin: plugin)
            if !plugin.identityConflictIDs.isEmpty {
                Section("plugins.identity.conflicts") {
                    ForEach(plugin.identityConflictIDs, id: \.self) { Text($0).font(.caption).textSelection(.enabled) }
                }
            }
            Section("plugins.detail.macho") {
                if let value = plugin.machOInstallName { detailRow("plugins.macho.install_name", value) }
                if let value = plugin.machOCurrentVersion { detailRow("plugins.macho.current_version", value) }
                if let value = plugin.machOCompatibilityVersion { detailRow("plugins.macho.compatibility_version", value) }
                if !plugin.machOUUIDs.isEmpty {
                    detailRow("plugins.macho.uuid", plugin.machOUUIDs.joined(separator: ", "))
                } else if let value = plugin.machOUUID { detailRow("plugins.macho.uuid", value) }
                detailRow("plugins.macho.architectures", plugin.machOArchitectures.isEmpty ? "—" : plugin.machOArchitectures.joined(separator: ", "))
                detailRow("plugins.macho.cdhash", plugin.machOCDHashes.isEmpty ? "—" : plugin.machOCDHashes.joined(separator: ", "))
                detailRow("plugins.macho.signature_state", plugin.codeSignatureStates.isEmpty ? "—" : plugin.codeSignatureStates.joined(separator: ", "))
                ForEach(plugin.machOSliceDetails, id: \.self) { Text($0).font(.caption).textSelection(.enabled) }
            }
            Section("plugins.detail.integrity") {
                if let hash = plugin.dylibSHA256 { detailRow("SHA-256 dylib", hash).textSelection(.enabled) }
                if let hash = plugin.plistSHA256 { detailRow("SHA-256 plist", hash).textSelection(.enabled) }
                ForEach(plugin.warnings, id: \.self) { Text(LocalizedStringKey($0)).font(.caption).foregroundStyle(.secondary) }
            }
            Section {
                Label("plugins.detail.read_only_notice", systemImage: "lock.shield")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(plugin.baseName)
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
    private var ownershipText: String {
        switch plugin.ownership {
        case .filterKit: return NSLocalizedString("plugins.ownership.filterkit", comment: "")
        case .packageManager: return NSLocalizedString("plugins.ownership.package_manager", comment: "")
        case .unknown: return NSLocalizedString("plugins.ownership.unknown", comment: "")
        }
    }
    private var permissionText: String {
        guard let permission = plugin.managementPermission else { return NSLocalizedString("plugins.permission.not_evaluated", comment: "") }
        return NSLocalizedString(permission.reasonKey, comment: "")
    }
    private var pairingText: String {
        switch plugin.pairingState {
        case .paired: return NSLocalizedString("plugins.pairing.paired", comment: "")
        case .orphanDylib: return NSLocalizedString("plugins.pairing.orphan_dylib", comment: "")
        case .orphanPlist: return NSLocalizedString("plugins.pairing.orphan_plist", comment: "")
        case .unreadable: return NSLocalizedString("plugins.pairing.unreadable", comment: "")
        case .invalid: return NSLocalizedString("plugins.pairing.invalid", comment: "")
        }
    }
}
