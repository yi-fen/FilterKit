import Foundation

/// Compatibility facade for existing P2-39 counters. All records now flow into
/// the structured developer JSONL stream; this type does not own another logger.
enum RuntimeDiagnosticsStore {
    static var logDirectoryURL: URL? { RuntimeEventLogger.logsDirectoryURL }
    static var currentLogURL: URL? { RuntimeEventLogger.developerLogURL }

    static func append(_ message: String) {
        RuntimeEventLogger.recordLegacyDiagnostic(message)
    }

    static func exportText() -> String {
        RuntimeEventLogger.developerLogText()
    }

    static func clear() {
        RuntimeEventLogger.clearDeveloperLogs()
    }
}
