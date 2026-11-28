import XCTest
@testable import FilterKit

final class PluginActivationPreflightTests: XCTestCase {
    private let permission = PluginManagementPermission(access: .manageable, reasonKey: "test")
    private let verifiedStrategy = EnableDisableStrategyResolution(
        strategy: .verifiedProfileStrategy, status: .verified,
        reasonKey: "test.verified", profileIdentifier: "test-rootHide")

    func testReferenceOnlyStrategyIsBlockedAndNeverMutates() {
        let input = makeInput(strategy: EnableDisableStrategyResolution(
            strategy: .unverified, status: .referenceOnly,
            reasonKey: "not-verified", profileIdentifier: "rootHide-reference"))
        let report = PluginActivationPreflight().evaluate(input, desiredState: .enabled)
        XCTAssertEqual(report.disposition, .blocked)
        XCTAssertTrue(report.blockers.contains(.enableDisableStrategyUnverified))
        XCTAssertFalse(report.canMutate)
        XCTAssertEqual(report.runtimeState, .notObserved)
    }

    func testNonFilterKitPluginIsNeverEligibleForManagement() {
        let input = makeInput(ownership: .packageManager)
        let report = PluginActivationPreflight().evaluate(input, desiredState: .disabled)
        XCTAssertTrue(report.blockers.contains(.pluginNotFilterKitOwned))
        XCTAssertTrue(report.blockers.contains(.managementPermissionDenied))
        XCTAssertFalse(report.canMutate)
    }

    func testFilterPlistObservationDoesNotClaimRuntimeInjection() {
        let configuration = PluginFilterConfiguration(
            parseState: .valid, containerKey: "Filter", bundles: ["com.example.target"],
            executables: [], classes: [], modeDescription: nil, unknownKeys: [], warnings: [])
        let report = PluginActivationPreflight().evaluate(
            makeInput(configuration: configuration), desiredState: .enabled)
        XCTAssertEqual(report.filterObservation, .targetListed)
        XCTAssertEqual(report.runtimeState, .notObserved)
        XCTAssertFalse(report.canMutate)
        XCTAssertEqual(report.disposition, .inspectionOnly)
        XCTAssertTrue(report.blockers.contains(.mutationReleaseClosed))
    }

    func testFilterObservationUsesCaseInsensitiveBundleIdentity() {
        let configuration = PluginFilterConfiguration(
            parseState: .valid, containerKey: "Filter", bundles: ["COM.EXAMPLE.TARGET"],
            executables: [], classes: [], modeDescription: nil, unknownKeys: [], warnings: [])
        let report = PluginActivationPreflight().evaluate(
            makeInput(configuration: configuration), desiredState: .enabled)
        XCTAssertEqual(report.filterObservation, .targetListed)
    }

    func testHardBoundActivationIsAllowedByPolicyButUncleanRecoveryStillBlocks() {
        let report = PluginActivationPreflight().evaluate(
            makeInput(isHardBound: true, recoveryIsClean: false), desiredState: .disabled)
        XCTAssertFalse(report.blockers.contains(.hardBoundAppCannotBeToggled))
        XCTAssertTrue(report.blockers.contains(.recoveryNotClean))
        XCTAssertFalse(report.canMutate)
    }

    private func makeInput(ownership: PluginOwnership = .filterKit,
                           pairing: PluginPairingState = .paired,
                           permission: PluginManagementPermission? = nil,
                           isHardBound: Bool = false,
                           targetAvailable: Bool = true,
                           environment: JailbreakEnvironmentKind = .rootHide,
                           elleKitPresent: Bool = true,
                           strategy: EnableDisableStrategyResolution? = nil,
                           helperReachable: Bool = true,
                           recoveryIsClean: Bool = true,
                           configuration: PluginFilterConfiguration? = nil) -> PluginActivationPreflightInput {
        PluginActivationPreflightInput(
            ownership: ownership, pairing: pairing, permission: permission ?? self.permission,
            isHardBoundApp: isHardBound, targetBundleIdentifier: "com.example.target",
            targetAppIsAvailable: targetAvailable, environment: environment,
            elleKitIsPresent: elleKitPresent, strategy: strategy ?? verifiedStrategy,
            helperIsReachable: helperReachable, recoveryIsClean: recoveryIsClean,
            filterConfiguration: configuration)
    }
}
