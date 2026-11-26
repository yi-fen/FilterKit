import Foundation
import SwiftUI

/// Shared read-only plugin inventory snapshot, mirroring R16's
/// `PluginFeatureStore` snapshot semantics. One background scan is reused by the
/// Plugins screen and association previews; the most recent successful result is
/// retained while a later refresh runs or fails, so the existing list never
/// falls back to a full-screen loading state during a background refresh.
///
/// This registry only coordinates scan timing and snapshot retention. It does
/// not read dylib binaries, query package ownership, verify hashes, write files,
/// or invoke the package manager.
@MainActor
final class PluginScanRegistry: ObservableObject {
    static let shared = PluginScanRegistry()

    /// Most recent successful inventory. `nil` only before the first scan completes.
    @Published private(set) var result: PluginScanResult?
    /// True while a background scan is active. The UI uses this only to show an
    /// inline progress row; an existing snapshot stays visible meanwhile.
    @Published private(set) var isLoading = false

    private let environment: ReadOnlyEnvironmentProvider
    private var inFlight: Task<PluginScanResult, Error>?

    init(environment: ReadOnlyEnvironmentProvider = ReadOnlyEnvironmentProvider()) {
        self.environment = environment
    }

    /// Warm the inventory off the foreground path. Safe to call at launch.
    func prewarm() {
        loadIfNeeded()
    }

    /// Reuse the active scan when one is running; otherwise start a background
    /// scan. A prior snapshot remains published during the refresh.
    func loadIfNeeded() {
        guard inFlight == nil else { return }
        isLoading = true

        let environment = environment
        let task = Task.detached(priority: .utility) { () -> PluginScanResult in
            // Environment probing and plugin enumeration both run off the main
            // actor; this must not block the first foreground frame.
            let report = environment.makeDiagnosticReport()
            let scanner = ReadOnlyPluginScanner(
                assessmentProvider: { report.pluginDirectoryAssessment }
            )
            return try await scanner.scanPlugins()
        }
        inFlight = task

        Task { @MainActor [weak self] in
            do {
                let scanned = try await task.value
                self?.result = scanned
            } catch {
                // Retain the last successful snapshot on failure; an unresolved
                // or inaccessible directory is still reported via the result's
                // directory state when there is no prior data.
            }
            self?.inFlight = nil
            self?.isLoading = false
        }
    }

    /// Force a fresh enumeration. Any prior snapshot stays visible until the new
    /// result lands.
    func refresh() {
        inFlight = nil
        loadIfNeeded()
    }
}
