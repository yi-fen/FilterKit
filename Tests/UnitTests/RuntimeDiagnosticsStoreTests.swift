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

    func testP239R3LogPathIsInsideApplicationSupport() {
        let path = RuntimeDiagnosticsStore.logDirectoryURL?.path ?? ""
        XCTAssertTrue(path.contains("Application Support"))
        XCTAssertTrue(path.hasSuffix("FilterKit/Logs"))
    }
}
