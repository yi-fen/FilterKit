import XCTest
@testable import FilterKit

final class RuntimeDiagnosticsStoreTests: XCTestCase {
    func testP239R3AppendExportAndClearLocalLog() throws {
        RuntimeDiagnosticsStore.clear()
        RuntimeDiagnosticsStore.append("[Test] diagnostics_round_trip=true")
        let exported = RuntimeDiagnosticsStore.exportText()
        XCTAssertTrue(exported.contains("diagnostics_round_trip=true"))
        XCTAssertTrue(exported.contains("[Test]"))
        RuntimeDiagnosticsStore.clear()
        XCTAssertFalse(RuntimeDiagnosticsStore.exportText().contains("diagnostics_round_trip=true"))
    }

    func testStructuredEventIsWrittenToDeveloperAndActivityStreams() {
        RuntimeEventLogger.clearDeveloperLogs()
        RuntimeEventLogger.clearActivity()
        RuntimeEventLogger.recordPluginOperation("import", succeeded: true,
            pluginID: "com.example.test", detail: "Imported test plugin.")
        let developer = RuntimeEventLogger.developerLogText()
        let activity = RuntimeEventLogger.recentActivity()
        XCTAssertTrue(developer.contains("plugin.import.completed"))
        XCTAssertTrue(developer.contains("com.example.test"))
        XCTAssertTrue(activity.contains { $0.eventName == "plugin.import.completed" })
    }

    func testDeveloperOnlyEventDoesNotAppearInActivityHistory() {
        RuntimeEventLogger.clearDeveloperLogs()
        RuntimeEventLogger.clearActivity()
        RuntimeEventLogger.record(level: .debug, module: "Test", event: "test.internal",
            message: "Developer-only event.")
        XCTAssertTrue(RuntimeEventLogger.developerLogText().contains("test.internal"))
        XCTAssertFalse(RuntimeEventLogger.recentActivity().contains { $0.eventName == "test.internal" })
    }

    func testP239R3LogPathIsInsideApplicationSupport() {
        let path = RuntimeDiagnosticsStore.logDirectoryURL?.path ?? ""
        XCTAssertTrue(path.contains("Application Support"))
        XCTAssertTrue(path.hasSuffix("FilterKit/Logs"))
    }
}
