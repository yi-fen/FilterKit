import Foundation

/// Deterministic fault-point catalogue for host tests and future Darwin integration. The matrix
/// describes required post-crash disposition; it does not inject faults into production code.
enum HelperInstallerCrashInjectionMatrix {
    enum Point: String, CaseIterable {
        case beforeJournalIntent
        case afterJournalIntentSync
        case afterStagedArtifactWrite
        case afterStagedDirectorySync
        case afterPreviousArtifactPreserve
        case afterActiveArtifactRename
        case afterActiveDirectorySync
        case afterPointerTemporaryWrite
        case afterPointerRename
        case afterPointerDirectorySync
        case beforeJournalCompletionSync
        case afterJournalCompletionSync
    }

    enum RequiredDisposition: Equatable { case reconcileBeforeAnyRetry, keepServiceStopped, verifyAllArtifactsAndPointer }

    static func disposition(for point: Point) -> RequiredDisposition {
        switch point {
        case .beforeJournalIntent:
            return .reconcileBeforeAnyRetry
        case .afterJournalIntentSync, .afterStagedArtifactWrite, .afterStagedDirectorySync,
             .afterPreviousArtifactPreserve, .afterActiveArtifactRename, .afterActiveDirectorySync,
             .afterPointerTemporaryWrite, .afterPointerRename, .afterPointerDirectorySync,
             .beforeJournalCompletionSync:
            return .keepServiceStopped
        case .afterJournalCompletionSync:
            return .verifyAllArtifactsAndPointer
        }
    }

    static var productionInjectionEnabled: Bool { false }
}
