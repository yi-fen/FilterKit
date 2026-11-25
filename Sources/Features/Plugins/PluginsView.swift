import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor
private final class PluginsViewModel: ObservableObject {
    @Published private(set) var result: PluginScanResult?
    @Published private(set) var isLoading = false
    @Published private(set) var errorKey: String?
    @Published var backupShareItem: ShareableBackup?
    @Published var backupErrorKey: String?
    @Published var restoreErrorKey: String?
    @Published var restoreReview: BackupRestoreReview?
    @Published var restoreNoticeKey: String?

    private let appDiscovery = LaunchServicesAppDiscoveryProvider()

    private let environment = ReadOnlyEnvironmentProvider()

    func exportAllManageable() {
        guard let result else { backupErrorKey = "backup.export.scan_required"; return }
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
            let currentScan = result
            let existingNames: Set<String>
            let conflictingIDs: Set<UUID>
            if let currentScan, currentScan.directoryState == .resolved {
                let directories = currentScan.scannedDirectories ?? currentScan.scannedDirectory.map { [$0] } ?? []
                let names = directories.flatMap { (try? FileManager.default.contentsOfDirectory(atPath: $0)) ?? [] }
                existingNames = Set(names)
                conflictingIDs = Set(currentScan.plugins.compactMap { item in
                    guard let raw = item.filterKitPluginID else { return nil }
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
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let report = environment.makeDiagnosticReport()
        guard let assessment = report.pluginDirectoryAssessment else {
            errorKey = "plugin_scan.directory_not_resolved"
            result = nil
            return
        }
        let ownershipProvider: PackageOwnershipProviding
        if let root = report.resolvedRootPath {
            ownershipProvider = DpkgFileOwnershipProvider(jbroot: root)
        } else {
            ownershipProvider = NoPackageOwnershipEvidenceProvider()
        }
        let scanner = ReadOnlyPluginScanner(packageOwnershipProvider: ownershipProvider,
                                            assessmentProvider: { assessment })
        do {
            let scanned = await Task.detached(priority: .utility) {
                scanner.scan(assessment: assessment)
            }.value
            result = scanned
            errorKey = nil
        } catch {
            errorKey = "plugin_scan.scan_failed"
        }
    }
}

struct PluginsView: View {
    @StateObject private var model = PluginsViewModel()
    @State private var showingAllPlugins = false
    @State private var searchText = ""
    @State private var isImportingBackup = false

    private var visiblePlugins: [PluginScanItem] {
        let items = model.result?.plugins ?? []
        return items.filter { item in
            let scopeMatches = showingAllPlugins || (item.managementPermission?.canModify == true)
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
                if model.isLoading && model.result == nil {
                    FKStateView(kind: .loading, systemImage: "puzzlepiece",
                                title: "plugins.loading.title", message: "plugins.loading.message")
                } else if let error = model.errorKey, model.result == nil {
                    FKStateView(kind: .error, systemImage: "exclamationmark.triangle",
                                title: "plugins.error.title", message: LocalizedStringKey(error),
                                actionTitle: "plugins.refresh") {
                        Task { await model.load() }
                    }
                } else if let result = model.result, result.directoryState != .resolved {
                    FKStateView(kind: .empty, systemImage: "folder.badge.questionmark",
                                title: "plugins.directory_unavailable.title",
                                message: result.directoryState == .ambiguous
                                    ? "plugins.directory_ambiguous.message" : "plugins.directory_unavailable.message",
                                actionTitle: "plugins.refresh") {
                        Task { await model.load() }
                    }
                } else if visiblePlugins.isEmpty {
                    FKStateView(kind: .empty, systemImage: "puzzlepiece",
                                title: searchText.isEmpty ? "plugins.empty.title" : "plugins.empty.search_title",
                                message: searchText.isEmpty ? "plugins.empty.message" : "plugins.empty.search_message",
                                actionTitle: "plugins.refresh") {
                        Task { await model.load() }
                    }
                } else {
                    List {
                        if let result = model.result {
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
                                    PluginScanRow(plugin: plugin)
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
                            Label("backup.restore.import", systemImage: "square.and.arrow.down")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("backup.actions")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showingAllPlugins.toggle() } label: {
                        Image(systemName: showingAllPlugins ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel(showingAllPlugins ? "plugins.scope.all" : "plugins.scope.managed")
                    .accessibilityValue(showingAllPlugins ? "plugins.scope.all" : "plugins.scope.managed")
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
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "puzzlepiece.extension.fill")
                .font(.title2).foregroundStyle(.secondary).frame(width: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(plugin.baseName).font(.body.weight(.medium))
                Text(plugin.dylibFileName ?? plugin.plistFileName ?? plugin.manifestFileName ?? plugin.id)
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Text(ownershipKey(plugin.ownership))
                    Text("·")
                    Text(pairingKey(plugin.pairingState))
                }.font(.caption2).foregroundStyle(.secondary)
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

    private func ownershipKey(_ ownership: PluginOwnership) -> LocalizedStringKey {
        switch ownership {
        case .filterKit: return "plugins.ownership.filterkit"
        case .packageManager: return "plugins.ownership.package_manager"
        case .unknown: return "plugins.ownership.unknown"
        }
    }
    private func pairingKey(_ state: PluginPairingState) -> LocalizedStringKey {
        switch state {
        case .paired: return "plugins.pairing.paired"
        case .orphanDylib: return "plugins.pairing.orphan_dylib"
        case .orphanPlist: return "plugins.pairing.orphan_plist"
        case .unreadable: return "plugins.pairing.unreadable"
        case .invalid: return "plugins.pairing.invalid"
        }
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
            if plugin.ownership == .filterKit {
                Section("plugins.detail.associations") {
                    detailRow("plugins.detail.hard_bound", plugin.hardBoundBundleIdentifier ?? "—")
                    ForEach(plugin.softAssociatedBundleIdentifiers, id: \.self) { Text($0) }
                }
            }
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
