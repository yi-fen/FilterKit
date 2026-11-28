import XCTest
@testable import FilterKit

final class AppPluginActivationOutcomeReconciliationTests: XCTestCase {
    private let reconciler = AppPluginActivationOutcomeReconciler()

    func testDesiredStateObservedDoesNotBecomeCommitProof() {
        let command = makeCommand(expected: false, desired: true)
        let observed = makeState(command: command, enabled: true)
        XCTAssertEqual(reconciler.resolve(command: command, observed: observed), .desiredStateObserved)
    }

    func testPreviousStateObservedIsReportedSeparately() {
        let command = makeCommand(expected: false, desired: true)
        let observed = makeState(command: command, enabled: false)
        XCTAssertEqual(reconciler.resolve(command: command, observed: observed), .previousStateObserved)
    }

    func testMismatchOrMissingObservationRemainsIndeterminate() {
        let command = makeCommand(expected: false, desired: true)
        XCTAssertEqual(reconciler.resolve(command: command, observed: nil), .stillIndeterminate)
        let mismatched = AppPluginActivationState(pluginID: command.pluginID.uuidString,
            pluginName: "Test", targetBundleIdentifier: "com.other.app", associationKind: .hardBound,
            observedState: .enabled, crossCheck: .matched, isHardBound: true,
            canPreviewToggle: true, readOnlyReasonKey: nil)
        XCTAssertEqual(reconciler.resolve(command: command, observed: mismatched), .stillIndeterminate)
    }

    func testInconsistentCrossCheckCannotResolveOutcome() {
        let command = makeCommand(expected: false, desired: true)
        let observed = AppPluginActivationState(pluginID: command.pluginID.uuidString,
            pluginName: "Test", targetBundleIdentifier: command.targetBundleIdentifier,
            associationKind: .hardBound, observedState: .enabled, crossCheck: .manifestFilterMismatch,
            isHardBound: true, canPreviewToggle: false, readOnlyReasonKey: "mismatch")
        XCTAssertEqual(reconciler.resolve(command: command, observed: observed), .stillIndeterminate)
    }

    private func makeCommand(expected: Bool, desired: Bool) -> HelperAppPluginActivationCommand {
        HelperAppPluginActivationCommand(requestID: UUID(), pluginID: UUID(),
            targetBundleIdentifier: "com.example.target", desiredEnabled: desired,
            expectedEnabled: expected, dylibFileName: "Test.dylib", plistFileName: "Test.plist",
            expectedFilterSHA256: String(repeating: "a", count: 64),
            expectedManifestSHA256: String(repeating: "b", count: 64), snapshotRevision: 1, createdAt: Date())
    }

    private func makeState(command: HelperAppPluginActivationCommand, enabled: Bool) -> AppPluginActivationState {
        AppPluginActivationState(pluginID: command.pluginID.uuidString,
            pluginName: "Test", targetBundleIdentifier: "com.example.target", associationKind: .hardBound,
            observedState: enabled ? .enabled : .disabled, crossCheck: .matched,
            isHardBound: true, canPreviewToggle: true, readOnlyReasonKey: nil)
    }
}
