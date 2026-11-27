import SwiftUI
import UIKit

struct RuntimeDiagnosticsView: View {
    @State private var showingShare = false
    @State private var showingClearConfirmation = false
    @State private var exportURL: URL?
    @State private var refreshID = UUID()

    private var app: AppDiscoveryPerformanceDiagnostics.Snapshot {
        _ = refreshID
        return AppDiscoveryPerformanceDiagnostics.snapshot()
    }
    private var plugin: PluginInventoryPerformanceDiagnostics.Snapshot {
        _ = refreshID
        return PluginInventoryPerformanceDiagnostics.snapshot()
    }

    var body: some View {
        Form {
            Section(header: Text("diagnostics.app_inventory")) {
                metric("diagnostics.app_entries", value: "\(app.appPageEntries)")
                metric("diagnostics.warm_entries", value: "\(app.warmInventoryEntries)")
                metric("diagnostics.plist_reads", value: "\(app.plistReads)")
                metric("diagnostics.plugin_snapshot_hits", value: "\(app.pluginSnapshotHits)")
                metric("diagnostics.plugin_snapshot_misses", value: "\(app.pluginSnapshotMisses)")
                metric("diagnostics.icon_file_reads", value: "\(app.iconFileReads)")
            }
            Section(header: Text("diagnostics.plugin_inventory")) {
                metric("diagnostics.inventory_scans", value: "\(plugin.inventoryScanCount)")
                metric("diagnostics.directory_enumerations", value: "\(plugin.directoryEnumerationCount)")
                metric("diagnostics.directory_listing_reuses", value: "\(plugin.directoryListingReuseCount)")
                metric("diagnostics.plugin_plist_reads", value: "\(plugin.pluginPlistReadCount)")
                metric("diagnostics.manifest_reads", value: "\(plugin.manifestReadCount)")
                metric("diagnostics.identity_analysis_count", value: "\(plugin.identityAnalysisCount)")
                metric("diagnostics.identity_analysis_ms", value: "\(plugin.identityAnalysisMilliseconds)")
                metric("diagnostics.environment_assessment_ms", value: "\(plugin.environmentAssessmentMilliseconds)")
                metric("diagnostics.plugin_scan_ms", value: "\(plugin.pluginDirectoryScanMilliseconds)")
                metric("diagnostics.changed_file_refreshes", value: "\(plugin.inventoryRefreshForChangedFilesCount)")
            }
            Section(header: Text("diagnostics.association")) {
                metric("diagnostics.snapshot_consumptions", value: "\(plugin.associationSnapshotConsumptions)")
                metric("diagnostics.reader_fallbacks", value: "\(plugin.associationReaderFallbacks)")
                metric("diagnostics.deferred_associations", value: "\(plugin.associationDeferredForAppSnapshot)")
            }
            Section(header: Text("diagnostics.attestation")) {
                metric("diagnostics.attestation_attempts", value: "\(plugin.attestationAttempts)")
                metric("diagnostics.attestation_verified", value: "\(plugin.attestationVerified)")
                metric("diagnostics.attestation_unavailable", value: "\(plugin.attestationUnavailable)")
                metric("diagnostics.attestation_rejected", value: "\(plugin.attestationRejected)")
                metric("diagnostics.attestation_errors", value: "\(plugin.attestationErrors)")
                metric("diagnostics.attestation_ms", value: "\(plugin.attestationMilliseconds)")
                metric("diagnostics.attestation_only_retries", value: "\(plugin.attestationOnlyRetryCount)")
            }
            Section(header: Text("diagnostics.local_logs")) {
                Text("diagnostics.local_only_note").font(.footnote).foregroundColor(.secondary)
                Text(RuntimeDiagnosticsStore.logDirectoryURL?.path ?? "—")
                    .font(.footnote).textSelection(.enabled)
                Button("diagnostics.export") { prepareExport() }
                Button("diagnostics.refresh") { refreshID = UUID() }
                Button("diagnostics.clear", role: .destructive) { showingClearConfirmation = true }
            }
        }
        .navigationTitle("diagnostics.title")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingShare, onDismiss: { if let url = exportURL { try? FileManager.default.removeItem(at: url) }; exportURL = nil }) {
            if let exportURL { ActivityViewController(activityItems: [exportURL]) }
        }
        .confirmationDialog("diagnostics.clear_confirm", isPresented: $showingClearConfirmation, titleVisibility: .visible) {
            Button("diagnostics.clear", role: .destructive) {
                RuntimeDiagnosticsStore.clear()
                refreshID = UUID()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func metric(_ title: LocalizedStringKey, value: String) -> some View {
        HStack { Text(title); Spacer(); Text(value).foregroundColor(.secondary).monospacedDigit() }
    }

    private func prepareExport() {
        let contents = RuntimeDiagnosticsStore.exportText()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("FilterKit-Diagnostics-\(Int(Date().timeIntervalSince1970)).log")
        do {
            try contents.write(to: url, atomically: true, encoding: .utf8)
            exportURL = url
            showingShare = true
        } catch { }
    }
}

private struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
