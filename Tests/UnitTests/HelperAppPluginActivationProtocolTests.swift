import XCTest
@testable import FilterKit

final class HelperAppPluginActivationProtocolTests: XCTestCase {
    private func command(desired: Bool = true, expected: Bool = false) -> HelperAppPluginActivationCommand {
        HelperAppPluginActivationCommand(requestID: UUID(), pluginID: UUID(),
            targetBundleIdentifier: "com.example.reader", desiredEnabled: desired, expectedEnabled: expected,
            dylibFileName: "Sample.dylib", plistFileName: "Sample.plist",
            expectedFilterSHA256: String(repeating: "a", count: 64),
            expectedManifestSHA256: String(repeating: "b", count: 64), snapshotRevision: 7, createdAt: Date())
    }

    func testCommandIsSingleTargetAndHashBound() {
        let value = command()
        XCTAssertTrue(value.validate())
        let mutation = value.makeMutationRequest()
        XCTAssertEqual(mutation.targetBundleIdentifier, value.targetBundleIdentifier)
        XCTAssertEqual(mutation.action, .enableForApp)
        XCTAssertEqual(mutation.expectedPlistSHA256, value.expectedFilterSHA256)
        XCTAssertEqual(mutation.expectedManifestSHA256, value.expectedManifestSHA256)
        XCTAssertNil(mutation.desiredSoftAssociations)
    }

    func testMalformedHashAndZeroRevisionAreRejected() {
        let value = command()
        let badHash = HelperAppPluginActivationCommand(requestID: value.requestID, pluginID: value.pluginID,
            targetBundleIdentifier: value.targetBundleIdentifier, desiredEnabled: value.desiredEnabled,
            expectedEnabled: value.expectedEnabled, dylibFileName: value.dylibFileName,
            plistFileName: value.plistFileName, expectedFilterSHA256: "bad",
            expectedManifestSHA256: value.expectedManifestSHA256, snapshotRevision: value.snapshotRevision, createdAt: value.createdAt)
        XCTAssertFalse(badHash.validate())
        let zeroRevision = HelperAppPluginActivationCommand(requestID: value.requestID, pluginID: value.pluginID,
            targetBundleIdentifier: value.targetBundleIdentifier, desiredEnabled: value.desiredEnabled,
            expectedEnabled: value.expectedEnabled, dylibFileName: value.dylibFileName,
            plistFileName: value.plistFileName, expectedFilterSHA256: value.expectedFilterSHA256,
            expectedManifestSHA256: value.expectedManifestSHA256, snapshotRevision: 0, createdAt: value.createdAt)
        XCTAssertFalse(zeroRevision.validate())
    }

    func testPlanRejectsStaleHashesOrDifferentTarget() {
        let value = command()
        let plan = HelperAppPluginActivationPlan(requestID: value.requestID, pluginID: value.pluginID,
            targetBundleIdentifier: value.targetBundleIdentifier, previousEnabled: false, desiredEnabled: true,
            filterBeforeSHA256: value.expectedFilterSHA256, filterAfterSHA256: String(repeating: "c", count: 64),
            manifestBeforeSHA256: value.expectedManifestSHA256, manifestAfterSHA256: String(repeating: "d", count: 64), changed: true)
        XCTAssertTrue(plan.validates(command: value))
        let wrongTarget = HelperAppPluginActivationCommand(requestID: value.requestID, pluginID: value.pluginID,
            targetBundleIdentifier: "com.example.other", desiredEnabled: true, expectedEnabled: false,
            dylibFileName: value.dylibFileName, plistFileName: value.plistFileName,
            expectedFilterSHA256: value.expectedFilterSHA256, expectedManifestSHA256: value.expectedManifestSHA256,
            snapshotRevision: value.snapshotRevision, createdAt: value.createdAt)
        XCTAssertFalse(plan.validates(command: wrongTarget))
    }

    func testProofMustBindRequestedStateAndTransactionSemantics() {
        let value = command()
        let proof = HelperAppPluginActivationProof(requestID: value.requestID, pluginID: value.pluginID,
            targetBundleIdentifier: value.targetBundleIdentifier, enabled: true,
            filterSHA256: String(repeating: "c", count: 64), manifestSHA256: String(repeating: "d", count: 64),
            transactionID: UUID(), completedAt: Date())
        XCTAssertTrue(proof.validates(command: value))
        let wrongState = HelperAppPluginActivationProof(requestID: value.requestID, pluginID: value.pluginID,
            targetBundleIdentifier: value.targetBundleIdentifier, enabled: false,
            filterSHA256: proof.filterSHA256, manifestSHA256: proof.manifestSHA256,
            transactionID: proof.transactionID, completedAt: proof.completedAt)
        XCTAssertFalse(wrongState.validates(command: value))
    }


    func testCommitRequestMustCarryExactPreparedPlan() {
        let value = command()
        let plan = HelperAppPluginActivationPlan(requestID: value.requestID, pluginID: value.pluginID,
            targetBundleIdentifier: value.targetBundleIdentifier, previousEnabled: false, desiredEnabled: true,
            filterBeforeSHA256: value.expectedFilterSHA256, filterAfterSHA256: String(repeating: "c", count: 64),
            manifestBeforeSHA256: value.expectedManifestSHA256, manifestAfterSHA256: String(repeating: "d", count: 64), changed: true)
        let request = HelperAppPluginActivationCommitRequest(requestID: UUID(), createdAt: Date(), command: value, preparedPlan: plan)
        XCTAssertTrue(request.validates())
        let tamperedPlan = HelperAppPluginActivationPlan(requestID: plan.requestID, pluginID: plan.pluginID,
            targetBundleIdentifier: plan.targetBundleIdentifier, previousEnabled: false, desiredEnabled: true,
            filterBeforeSHA256: plan.filterBeforeSHA256, filterAfterSHA256: String(repeating: "e", count: 64),
            manifestBeforeSHA256: plan.manifestBeforeSHA256, manifestAfterSHA256: plan.manifestAfterSHA256, changed: true)
        XCTAssertFalse(HelperAppPluginActivationCommitRequest(requestID: UUID(), createdAt: Date(), command: value, preparedPlan: tamperedPlan).validates())
    }


    func testCommitUsesFreshRequestIDToAvoidPrepareReplayCollision() {
        let value = command()
        let plan = HelperAppPluginActivationPlan(requestID: value.requestID, pluginID: value.pluginID,
            targetBundleIdentifier: value.targetBundleIdentifier, previousEnabled: false, desiredEnabled: true,
            filterBeforeSHA256: value.expectedFilterSHA256, filterAfterSHA256: String(repeating: "c", count: 64),
            manifestBeforeSHA256: value.expectedManifestSHA256, manifestAfterSHA256: String(repeating: "d", count: 64), changed: true)
        XCTAssertFalse(HelperAppPluginActivationCommitRequest(requestID: value.requestID, createdAt: Date(),
            command: value, preparedPlan: plan).validates())
        XCTAssertTrue(HelperAppPluginActivationCommitRequest(requestID: UUID(), createdAt: Date(),
            command: value, preparedPlan: plan).validates())
    }

    func testNoOpProofCannotClaimTransaction() {
        let value = command(desired: false, expected: false)
        let proof = HelperAppPluginActivationProof(requestID: value.requestID, pluginID: value.pluginID,
            targetBundleIdentifier: value.targetBundleIdentifier, enabled: false,
            filterSHA256: value.expectedFilterSHA256, manifestSHA256: value.expectedManifestSHA256,
            transactionID: UUID(), completedAt: Date())
        XCTAssertFalse(proof.validates(command: value))
    }
}
