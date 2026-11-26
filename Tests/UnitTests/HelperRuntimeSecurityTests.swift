import XCTest
@testable import FilterKit

final class HelperRuntimeSecurityTests: XCTestCase {
    func testLifecyclePlanNeverRunsFromApp() throws {
        let plan = try HelperLifecyclePlan.make(action: .install, jbRoot: "/var/containers/jb")
        XCTAssertTrue(plan.requiresRootInstaller)
        XCTAssertFalse(plan.mayRunFromApp)
        XCTAssertTrue(plan.requiresFreshCDHashes)
        XCTAssertEqual(plan.artifacts.first(where: { $0.kind == .manifest })?.modeOctal, "0600")
        XCTAssertEqual(plan.artifacts.first(where: { $0.kind == .ipcParentDirectory })?.modeOctal, "0711")
        XCTAssertEqual(plan.artifacts.first(where: { $0.kind == .auditDirectory })?.modeOctal, "0711")
        XCTAssertEqual(plan.artifacts.first(where: { $0.kind == .socket })?.modeOctal, "0660")
        XCTAssertEqual(plan.artifacts.first(where: { $0.kind == .socket })?.owner, "root:501")
    }

    func testLifecyclePlanRejectsTraversalAndInvalidFingerprint() {
        XCTAssertThrowsError(try HelperLifecyclePlan.make(action: .install, jbRoot: "/var/jb/../bad"))
        XCTAssertThrowsError(try HelperLifecyclePlan.make(action: .repin, jbRoot: "/var/jb", executableCDHash: "not-a-hash"))
    }

    func testDisabledManifestTemplateRemainsDisabled() {
        let manifest = HelperDeploymentManifest.disabledTemplate(routeIdentifier: "roothide",
            jbRootPath: "/var/jb", tweakInjectPath: "/var/jb/usr/lib/TweakInject",
            stagingRootPath: "/var/mobile/Library/FilterKit/Staging", socketPath: "/var/jb/Library/FilterKit/Helper/helper.sock")
        XCTAssertFalse(manifest.executionEnabled)
        XCTAssertEqual(manifest.socketGroupID, 501)
        XCTAssertTrue(manifest.allowedAppCDHashes.isEmpty)
        XCTAssertTrue(manifest.allowedHelperCDHashes.isEmpty)
    }
}

final class HelperSocketAccessPolicyTests: XCTestCase {
    func testMissingSocketGroupFailsClosedBeforeListenerStartup() {
        var manifest = HelperDeploymentManifest.disabledTemplate(routeIdentifier: "roothide",
            jbRootPath: "/var/jb", tweakInjectPath: "/var/jb/usr/lib/TweakInject",
            stagingRootPath: "/var/mobile/Library/FilterKit/Staging",
            socketPath: "/var/jb/Library/FilterKit/Helper/helper.sock")
        manifest.socketGroupID = nil
        XCTAssertThrowsError(try HelperTrustConfigurationValidator.validate(manifest))
    }

    func testZeroSocketGroupIsRejected() {
        XCTAssertThrowsError(try HelperLifecyclePlan.make(action: .install, jbRoot: "/var/jb", socketGroupID: 0))
    }
}
