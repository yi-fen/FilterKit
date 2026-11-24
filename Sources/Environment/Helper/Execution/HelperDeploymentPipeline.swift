import Foundation

/// Result returned only after the paired file transaction reports success.
struct HelperDeploymentBatchReceipt: Codable, Equatable {
    enum Route: String, Codable { case firstInstall, update }
    let batchID: UUID
    let pluginID: UUID
    let route: Route
    let requestIDs: [UUID]
    let changedPaths: [String]
    let dylibSHA256: String
    let plistSHA256: String
    let completedAt: Date
    let manifestSHA256: String?
}

/// Root-side evidence used to select one authorization path. `manifestExists` and `ownership`
/// must be derived by the backend from filesystem and package-manager evidence, never IPC fields.
struct HelperDeploymentRouteEvidence: Equatable {
    let manifestExists: Bool
    let ownership: HelperDeploymentRouteResolver.OwnershipEvidence
}

/// A prepared deployment is produced only after the backend has completed the route-specific
/// checks. The pipeline independently checks that the proof and plans bind the submitted batch.
struct HelperExpectedPreviousDeployment: Equatable {
    let dylibSHA256: String
    let plistSHA256: String
    let manifestSHA256: String
}

struct HelperAuthorizedDeployment {
    let proof: HelperOwnershipProof
    let plans: [HelperClosedExecutionPlan]
    /// Root-validated payload bytes and the exact Schema 3 Manifest bytes are kept inside the
    /// Helper process; they are never accepted as separate IPC authority claims.
    let dylibData: Data?
    let plistData: Data?
    let manifestData: Data?
    let expectedPrevious: HelperExpectedPreviousDeployment?

    init(proof: HelperOwnershipProof, plans: [HelperClosedExecutionPlan],
         dylibData: Data? = nil, plistData: Data? = nil, manifestData: Data? = nil,
         expectedPrevious: HelperExpectedPreviousDeployment? = nil) {
        self.proof = proof; self.plans = plans
        self.dylibData = dylibData; self.plistData = plistData; self.manifestData = manifestData
        self.expectedPrevious = expectedPrevious
    }
}

/// Platform adapter contract. A production implementation must use the concrete root-side
/// manifest/bootstrap, package ownership, Mach-O/plist verification, policy and safe executor
/// components. Tests may inject a deterministic fake, but that fake is never used by Runtime.
protocol HelperDeploymentPipelineBackend {
    func inspectRoute(batch: HelperDeploymentBatchRequest, context: HelperAuthenticatedPeerContext) throws -> HelperDeploymentRouteEvidence
    func authorizeFirstInstall(batch: HelperDeploymentBatchRequest, context: HelperAuthenticatedPeerContext) throws -> HelperAuthorizedDeployment
    func authorizeUpdate(batch: HelperDeploymentBatchRequest, context: HelperAuthenticatedPeerContext) throws -> HelperAuthorizedDeployment
    func execute(_ prepared: HelperAuthorizedDeployment) throws -> HelperSafeFileExecutor.TransactionReceipt
}

struct HelperDeploymentPipeline {
    enum PipelineError: Error, Equatable {
        case invalidBatch, proofMismatch, planMismatch, authorizationFailed, executionFailed
    }

    private let backend: HelperDeploymentPipelineBackend
    private let routeResolver = HelperDeploymentRouteResolver()

    init(backend: HelperDeploymentPipelineBackend) { self.backend = backend }

    func execute(_ batch: HelperDeploymentBatchRequest,
                 context: HelperAuthenticatedPeerContext,
                 now: Date = Date()) throws -> HelperDeploymentBatchReceipt {
        try batch.validate(now: now)
        let pair: (pluginID: UUID, dylib: HelperOperationRequest, plist: HelperOperationRequest)
        do { pair = try HelperDeploymentBatchValidator().validate(batch.operations) }
        catch { throw PipelineError.invalidBatch }
        guard pair.pluginID == batch.pluginID else { throw PipelineError.invalidBatch }

        let evidence: HelperDeploymentRouteEvidence
        do { evidence = try backend.inspectRoute(batch: batch, context: context) }
        catch { throw PipelineError.authorizationFailed }
        let route: HelperDeploymentRouteResolver.Route
        do {
            route = try routeResolver.resolve(requests: batch.operations,
                manifestExists: evidence.manifestExists, ownership: evidence.ownership)
        } catch { throw PipelineError.authorizationFailed }

        let prepared: HelperAuthorizedDeployment
        do {
            switch route {
            case .firstInstall:
                prepared = try backend.authorizeFirstInstall(batch: batch, context: context)
            case .update:
                prepared = try backend.authorizeUpdate(batch: batch, context: context)
            }
        } catch { throw PipelineError.authorizationFailed }

        try validate(prepared, pair: pair, expectedFirstInstall: route == .firstInstall)
        let transaction: HelperSafeFileExecutor.TransactionReceipt
        do { transaction = try backend.execute(prepared) }
        catch { throw PipelineError.executionFailed }

        guard transaction.pluginID == pair.pluginID,
              Set(transaction.requestIDs) == Set(batch.operations.map(\.requestID)),
              Set(transaction.changedPaths) == Set([pair.dylib.targetFileName, pair.plist.targetFileName]),
              transaction.dylibSHA256.caseInsensitiveCompare(pair.dylib.expectedSHA256 ?? "") == .orderedSame,
              transaction.plistSHA256.caseInsensitiveCompare(pair.plist.expectedSHA256 ?? "") == .orderedSame,
              (prepared.manifestData == nil || transaction.manifestSHA256?.caseInsensitiveCompare(SHA256Digest.hex(prepared.manifestData!)) == .orderedSame) else {
            // A backend returning an inconsistent receipt is treated as a hard failure. The
            // transaction may already have committed; caller must reconcile via durable journal.
            throw PipelineError.executionFailed
        }
        return HelperDeploymentBatchReceipt(batchID: batch.batchID, pluginID: pair.pluginID,
            route: route == .firstInstall ? .firstInstall : .update,
            requestIDs: transaction.requestIDs,
            changedPaths: transaction.changedPaths.sorted(),
            dylibSHA256: transaction.dylibSHA256, plistSHA256: transaction.plistSHA256,
            completedAt: transaction.completedAt, manifestSHA256: transaction.manifestSHA256)
    }

    private func validate(_ prepared: HelperAuthorizedDeployment,
                          pair: (pluginID: UUID, dylib: HelperOperationRequest, plist: HelperOperationRequest),
                          expectedFirstInstall: Bool) throws {
        let proof = prepared.proof
        guard proof.pluginID == pair.pluginID,
              proof.dylibFileName == pair.dylib.targetFileName,
              proof.plistFileName == pair.plist.targetFileName,
              proof.dylibSHA256.caseInsensitiveCompare(pair.dylib.expectedSHA256 ?? "") == .orderedSame,
              proof.plistSHA256.caseInsensitiveCompare(pair.plist.expectedSHA256 ?? "") == .orderedSame,
              proof.binaryIdentityVerified, proof.manifestSchemaVersion >= 3,
              proof.isFirstInstallAuthorization == expectedFirstInstall else {
            throw PipelineError.proofMismatch
        }
        if expectedFirstInstall {
            guard prepared.expectedPrevious == nil else { throw PipelineError.proofMismatch }
        } else {
            guard let previous = prepared.expectedPrevious,
                  HelperPolicy.isValidHash(previous.dylibSHA256),
                  HelperPolicy.isValidHash(previous.plistSHA256),
                  HelperPolicy.isValidHash(previous.manifestSHA256) else { throw PipelineError.proofMismatch }
        }
        if let dylibData = prepared.dylibData, let plistData = prepared.plistData, let manifestData = prepared.manifestData {
            guard SHA256Digest.hex(dylibData).caseInsensitiveCompare(proof.dylibSHA256) == .orderedSame,
                  SHA256Digest.hex(plistData).caseInsensitiveCompare(proof.plistSHA256) == .orderedSame,
                  SHA256Digest.hex(manifestData).caseInsensitiveCompare(proof.manifestSHA256) == .orderedSame else {
                throw PipelineError.proofMismatch
            }
        } else if prepared.dylibData != nil || prepared.plistData != nil || prepared.manifestData != nil {
            throw PipelineError.proofMismatch
        }
        guard prepared.plans.count == 2,
              let dylibPlan = prepared.plans.first(where: { $0.operation == .installDylib }),
              let plistPlan = prepared.plans.first(where: { $0.operation == .replaceFilterPlist }),
              prepared.plans.allSatisfy({ $0.pluginID == pair.pluginID && $0.action == .copyFile }),
              dylibPlan.requestID == pair.dylib.requestID,
              plistPlan.requestID == pair.plist.requestID,
              dylibPlan.sourceRelativePath == pair.dylib.stagingRelativePath,
              plistPlan.sourceRelativePath == pair.plist.stagingRelativePath,
              dylibPlan.destinationRelativePath == pair.dylib.targetFileName,
              plistPlan.destinationRelativePath == pair.plist.targetFileName,
              dylibPlan.expectedSHA256?.lowercased() == pair.dylib.expectedSHA256?.lowercased(),
              plistPlan.expectedSHA256?.lowercased() == pair.plist.expectedSHA256?.lowercased() else {
            throw PipelineError.planMismatch
        }
    }
}
