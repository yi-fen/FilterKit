import Foundation

/// Process-local profiling for plugin inventory and Helper identity attestation.
/// Helper IPC timings are intentionally separated from directory enumeration.
enum PluginInventoryPerformanceDiagnostics {
    struct Snapshot {
        let inventoryScanCount: Int
        let environmentAssessmentMilliseconds: UInt64
        let pluginDirectoryScanMilliseconds: UInt64
        let directoryEnumerationCount: Int
        let directoryListingReuseCount: Int
        let pluginPlistReadCount: Int
        let manifestReadCount: Int
        let identityAnalysisCount: Int
        let identityAnalysisMilliseconds: UInt64
        let attestationOnlyRetryCount: Int
        let inventoryRefreshForChangedFilesCount: Int
        let associationSnapshotConsumptions: Int
        let associationReaderFallbacks: Int
        let associationDeferredForAppSnapshot: Int
        let attestationAttempts: Int
        let attestationVerified: Int
        let attestationUnavailable: Int
        let attestationRejected: Int
        let attestationErrors: Int
        let attestationMilliseconds: UInt64
    }
    enum Outcome { case verified, rejected, unavailable, error }
    private static let lock = NSLock()
    private static var inventoryScanCount = 0
    private static var environmentAssessmentMilliseconds: UInt64 = 0
    private static var pluginDirectoryScanMilliseconds: UInt64 = 0
    private static var directoryEnumerationCount = 0
    private static var directoryListingReuseCount = 0
    private static var pluginPlistReadCount = 0
    private static var manifestReadCount = 0
    private static var identityAnalysisCount = 0
    private static var identityAnalysisMilliseconds: UInt64 = 0
    private static var attestationOnlyRetryCount = 0
    private static var inventoryRefreshForChangedFilesCount = 0
    private static var associationSnapshotConsumptions = 0
    private static var associationReaderFallbacks = 0
    private static var associationDeferredForAppSnapshot = 0
    private static var attestationAttempts = 0
    private static var attestationVerified = 0
    private static var attestationUnavailable = 0
    private static var attestationRejected = 0
    private static var attestationErrors = 0
    private static var attestationMilliseconds: UInt64 = 0

    static func recordInventoryScanStarted() { lock.lock(); inventoryScanCount += 1; lock.unlock() }
    static func recordEnvironmentAssessment(milliseconds: UInt64) { lock.lock(); environmentAssessmentMilliseconds += milliseconds; lock.unlock() }
    static func recordPluginDirectoryScan(milliseconds: UInt64) { lock.lock(); pluginDirectoryScanMilliseconds += milliseconds; lock.unlock() }
    static func recordDirectoryEnumeration() { lock.lock(); directoryEnumerationCount += 1; lock.unlock() }
    static func recordDirectoryListingReuse() { lock.lock(); directoryListingReuseCount += 1; lock.unlock() }
    static func recordPluginPlistRead() { lock.lock(); pluginPlistReadCount += 1; lock.unlock() }
    static func recordManifestRead() { lock.lock(); manifestReadCount += 1; lock.unlock() }
    static func recordIdentityAnalysis(milliseconds: UInt64) {
        lock.lock(); identityAnalysisCount += 1; identityAnalysisMilliseconds += milliseconds; lock.unlock()
    }
    static func recordAttestationOnlyRetry() { lock.lock(); attestationOnlyRetryCount += 1; lock.unlock() }
    static func recordInventoryRefreshForChangedFiles() { lock.lock(); inventoryRefreshForChangedFilesCount += 1; lock.unlock() }
    static func recordAssociationSnapshotConsumption() { lock.lock(); associationSnapshotConsumptions += 1; lock.unlock() }
    static func recordAssociationReaderFallback() { lock.lock(); associationReaderFallbacks += 1; lock.unlock() }
    static func recordAssociationDeferredForAppSnapshot() { lock.lock(); associationDeferredForAppSnapshot += 1; lock.unlock() }
    static func recordAttestation(milliseconds: UInt64, outcome: Outcome) {
        lock.lock(); defer { lock.unlock() }
        attestationAttempts += 1; attestationMilliseconds += milliseconds
        switch outcome {
        case .verified: attestationVerified += 1
        case .unavailable: attestationUnavailable += 1
        case .rejected: attestationRejected += 1
        case .error: attestationErrors += 1
        }
    }
    static func elapsedMilliseconds(since start: UInt64) -> UInt64 {
        (DispatchTime.now().uptimeNanoseconds &- start) / 1_000_000
    }
    static func snapshot() -> Snapshot {
        lock.lock(); defer { lock.unlock() }
        return Snapshot(inventoryScanCount: inventoryScanCount,
            environmentAssessmentMilliseconds: environmentAssessmentMilliseconds,
            pluginDirectoryScanMilliseconds: pluginDirectoryScanMilliseconds,
            directoryEnumerationCount: directoryEnumerationCount,
            directoryListingReuseCount: directoryListingReuseCount,
            pluginPlistReadCount: pluginPlistReadCount,
            manifestReadCount: manifestReadCount,
            identityAnalysisCount: identityAnalysisCount,
            identityAnalysisMilliseconds: identityAnalysisMilliseconds,
            attestationOnlyRetryCount: attestationOnlyRetryCount,
            inventoryRefreshForChangedFilesCount: inventoryRefreshForChangedFilesCount,
            associationSnapshotConsumptions: associationSnapshotConsumptions,
            associationReaderFallbacks: associationReaderFallbacks,
            associationDeferredForAppSnapshot: associationDeferredForAppSnapshot,
            attestationAttempts: attestationAttempts, attestationVerified: attestationVerified,
            attestationUnavailable: attestationUnavailable, attestationRejected: attestationRejected,
            attestationErrors: attestationErrors, attestationMilliseconds: attestationMilliseconds)
    }
    static func logSummaryIfNeeded() {
        let v = snapshot()
        let line = "[PluginInventory][P2-39-R3] scans=\(v.inventoryScanCount) environment_assessment_ms=\(v.environmentAssessmentMilliseconds) plugin_directory_scan_ms=\(v.pluginDirectoryScanMilliseconds) directory_enumerations=\(v.directoryEnumerationCount) directory_listing_reuses=\(v.directoryListingReuseCount) plugin_plist_reads=\(v.pluginPlistReadCount) manifest_reads=\(v.manifestReadCount) identity_analysis_count=\(v.identityAnalysisCount) identity_analysis_ms=\(v.identityAnalysisMilliseconds) attestation_only_retries=\(v.attestationOnlyRetryCount) inventory_refresh_file_changes=\(v.inventoryRefreshForChangedFilesCount) association_snapshot_consumptions=\(v.associationSnapshotConsumptions) association_reader_fallbacks=\(v.associationReaderFallbacks) association_deferred_no_app_snapshot=\(v.associationDeferredForAppSnapshot) attestation_attempts=\(v.attestationAttempts) attestation_verified=\(v.attestationVerified) attestation_unavailable=\(v.attestationUnavailable) attestation_rejected=\(v.attestationRejected) attestation_errors=\(v.attestationErrors) attestation_ms=\(v.attestationMilliseconds)"
        RuntimeDiagnosticsStore.append(line)
        #if DEBUG
        NSLog("[FilterKit] %@", line)
        #endif
    }
}
