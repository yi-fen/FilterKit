import Foundation

func require128(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw NSError(domain: "P1-28", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}

final class FakeP128Backend: HelperDeploymentPipelineBackend {
    var evidence: HelperDeploymentRouteEvidence
    var shouldFailAuthorization = false
    var corruptReceipt = false
    init(evidence: HelperDeploymentRouteEvidence) { self.evidence = evidence }

    func inspectRoute(batch: HelperDeploymentBatchRequest, context: HelperAuthenticatedPeerContext) throws -> HelperDeploymentRouteEvidence { evidence }
    func authorizeFirstInstall(batch: HelperDeploymentBatchRequest, context: HelperAuthenticatedPeerContext) throws -> HelperAuthorizedDeployment {
        try makePrepared(batch.operations, firstInstall: true)
    }
    func authorizeUpdate(batch: HelperDeploymentBatchRequest, context: HelperAuthenticatedPeerContext) throws -> HelperAuthorizedDeployment {
        try makePrepared(batch.operations, firstInstall: false)
    }
    private func makePrepared(_ requests: [HelperOperationRequest], firstInstall: Bool) throws -> HelperAuthorizedDeployment {
        if shouldFailAuthorization { throw NSError(domain: "fake", code: 1) }
        let pair = try HelperDeploymentBatchValidator().validate(requests)
        let proof = try HelperOwnershipProof(pluginID: pair.pluginID,
            dylibFileName: pair.dylib.targetFileName, plistFileName: pair.plist.targetFileName,
            dylibSHA256: pair.dylib.expectedSHA256!, plistSHA256: pair.plist.expectedSHA256!,
            manifestSchemaVersion: 3, manifestSHA256: String(repeating: "c", count: 64),
            binaryIdentityVerified: true, isFirstInstallAuthorization: firstInstall)
        let plans = [
            HelperClosedExecutionPlan(requestID: pair.dylib.requestID, pluginID: pair.pluginID, action: .copyFile,
                sourceRelativePath: pair.dylib.stagingRelativePath, destinationRelativePath: pair.dylib.targetFileName,
                expectedSHA256: pair.dylib.expectedSHA256, operation: .installDylib),
            HelperClosedExecutionPlan(requestID: pair.plist.requestID, pluginID: pair.pluginID, action: .copyFile,
                sourceRelativePath: pair.plist.stagingRelativePath, destinationRelativePath: pair.plist.targetFileName,
                expectedSHA256: pair.plist.expectedSHA256, operation: .replaceFilterPlist)
        ]
        let previous = firstInstall ? nil : HelperExpectedPreviousDeployment(
            dylibSHA256: String(repeating: "1", count: 64),
            plistSHA256: String(repeating: "2", count: 64),
            manifestSHA256: String(repeating: "3", count: 64))
        return HelperAuthorizedDeployment(proof: proof, plans: plans, expectedPrevious: previous)
    }
    func execute(_ prepared: HelperAuthorizedDeployment) throws -> HelperSafeFileExecutor.TransactionReceipt {
        let paths = prepared.plans.map(\.destinationRelativePath).sorted()
        return HelperSafeFileExecutor.TransactionReceipt(requestIDs: prepared.plans.map(\.requestID), pluginID: prepared.proof.pluginID,
            changedPaths: corruptReceipt ? ["foreign"] : paths,
            dylibSHA256: prepared.proof.dylibSHA256, plistSHA256: prepared.proof.plistSHA256, completedAt: Date())
    }
}

@main struct P128PipelineSmoke {
    static func main() throws {
        let pluginID = UUID(), now = Date()
        let operations = [
            HelperOperationRequest(requestID: UUID(), operation: .installDylib, pluginID: pluginID,
                stagingRelativePath: "task/Widget.dylib", targetFileName: "Widget.dylib",
                expectedSHA256: String(repeating: "a", count: 64), createdAt: now),
            HelperOperationRequest(requestID: UUID(), operation: .replaceFilterPlist, pluginID: pluginID,
                stagingRelativePath: "task/Widget.plist", targetFileName: "Widget.plist",
                expectedSHA256: String(repeating: "b", count: 64), createdAt: now)
        ]
        let batch = try HelperDeploymentBatchRequest.make(pluginID: pluginID, operations: operations, createdAt: now)
        let peer = HelperPeerIdentity(uid: 501, gid: 501, pid: 123, cdHashHex: String(repeating: "d", count: 40), pidVersion: nil, auditSessionID: nil)
        let context = HelperAuthenticatedPeerContext(peer: .init(uid: 501, gid: 501, pid: 123), identity: peer,
            sessionNonce: String(repeating: "e", count: 32), authenticatedAt: now)

        let firstBackend = FakeP128Backend(evidence: .init(manifestExists: false, ownership: .verifiedUnowned))
        let first = try HelperDeploymentPipeline(backend: firstBackend).execute(batch, context: context, now: now)
        try require128(first.route == .firstInstall && first.changedPaths.count == 2, "first-install pipeline failed")

        let updateBackend = FakeP128Backend(evidence: .init(manifestExists: true, ownership: .filterKitOwned))
        let update = try HelperDeploymentPipeline(backend: updateBackend).execute(batch, context: context, now: now)
        try require128(update.route == .update, "update pipeline failed")

        let blockedBackend = FakeP128Backend(evidence: .init(manifestExists: false, ownership: .unknown))
        do { _ = try HelperDeploymentPipeline(backend: blockedBackend).execute(batch, context: context, now: now); throw NSError(domain: "P1-28", code: 2) }
        catch HelperDeploymentPipeline.PipelineError.authorizationFailed { }

        let failedAuth = FakeP128Backend(evidence: .init(manifestExists: false, ownership: .verifiedUnowned))
        failedAuth.shouldFailAuthorization = true
        do { _ = try HelperDeploymentPipeline(backend: failedAuth).execute(batch, context: context, now: now); throw NSError(domain: "P1-28", code: 3) }
        catch HelperDeploymentPipeline.PipelineError.authorizationFailed { }

        let badReceipt = FakeP128Backend(evidence: .init(manifestExists: false, ownership: .verifiedUnowned))
        badReceipt.corruptReceipt = true
        do { _ = try HelperDeploymentPipeline(backend: badReceipt).execute(batch, context: context, now: now); throw NSError(domain: "P1-28", code: 4) }
        catch HelperDeploymentPipeline.PipelineError.executionFailed { }

        print("P1-28 pipeline smoke: PASS (first-install, update, unknown-ownership rejection, authorization failure, receipt integrity)")
    }
}
