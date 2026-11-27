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
        #if DEBUG
        let v = snapshot()
        NSLog("[FilterKit][PluginInventory][P2-39-R1] scans=%d environment_assessment_ms=%llu plugin_directory_scan_ms=%llu directory_enumerations=%d directory_listing_reuses=%d attestation_only_retries=%d inventory_refresh_file_changes=%d association_snapshot_consumptions=%d association_reader_fallbacks=%d association_deferred_no_app_snapshot=%d attestation_attempts=%d attestation_verified=%d attestation_unavailable=%d attestation_rejected=%d attestation_errors=%d attestation_ms=%llu",
              v.inventoryScanCount, v.environmentAssessmentMilliseconds, v.pluginDirectoryScanMilliseconds,
              v.directoryEnumerationCount, v.directoryListingReuseCount, v.attestationOnlyRetryCount,
              v.inventoryRefreshForChangedFilesCount, v.associationSnapshotConsumptions,
              v.associationReaderFallbacks, v.associationDeferredForAppSnapshot, v.attestationAttempts,
              v.attestationVerified, v.attestationUnavailable, v.attestationRejected,
              v.attestationErrors, v.attestationMilliseconds)
        #endif
    }
}
