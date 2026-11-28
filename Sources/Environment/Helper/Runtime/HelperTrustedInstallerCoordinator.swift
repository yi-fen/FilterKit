import Foundation

/// Immutable proof that the release envelope, exact artifact set, and provisioning payload
/// agree. Its initializer is private so execution cannot be requested with caller-built claims.
struct HelperPreparedRootInstall: Equatable {
    let plan: HelperInstallerTransactionPlan
    let release: HelperRootReleaseSet.Verified
    let provisioningEnvelopeSHA256: String
    let provisioningEnvelopeData: Data
    let initialJournal: HelperInstallerTransactionJournal

    fileprivate init(plan: HelperInstallerTransactionPlan,
                     release: HelperRootReleaseSet.Verified,
                     provisioningEnvelopeSHA256: String,
                     provisioningEnvelopeData: Data,
                     initialJournal: HelperInstallerTransactionJournal) {
        self.plan = plan
        self.release = release
        self.provisioningEnvelopeSHA256 = provisioningEnvelopeSHA256
        self.provisioningEnvelopeData = provisioningEnvelopeData
        self.initialJournal = initialJournal
    }
}

/// Narrow adapter contract for a future privileged installer. No production implementation is
/// supplied in this release: callers cannot turn this protocol into an enabled production path.
protocol HelperRootInstallerExecuting {
    var isProductionReady: Bool { get }
    /// The adapter must persist and advance the durable release journal around every step.
    /// It calls `commitProvisioning` only after the new release is activated and verified.
    /// A rejected provisioning commit permits rollback; an indeterminate commit requires the
    /// adapter to keep the new release activated but stopped and journal manual intervention.
    func execute(_ prepared: HelperPreparedRootInstall,
                 commitProvisioning: () throws -> HelperInstallerProvisioningCommitResult) throws
}

struct HelperUnavailableRootInstaller: HelperRootInstallerExecuting {
    var isProductionReady: Bool { false }
    func execute(_ prepared: HelperPreparedRootInstall,
                 commitProvisioning: () throws -> HelperInstallerProvisioningCommitResult) throws {
        throw HelperTrustedInstallerCoordinator.Failure.rootInstallerUnavailable
    }
}

/// Joins the R7 signed envelope, R8 trusted provisioning store, release artifact verification,
/// durable journal, shared cross-process lock, and the existing execution gate. `prepare` is
/// read-only. `execute` remains fail-closed until a separately reviewed production adapter and
/// an explicitly released transaction plan exist.
struct HelperTrustedInstallerCoordinator {
    enum Failure: Error, Equatable {
        case unsupportedAction, rootMismatch, provisioningEnvelopeInvalid
        case provisioningMismatch, releaseVerificationFailed, journalCreationFailed
        case provisioningCommitRejected, provisioningCommitIndeterminate
        case executionBlocked(HelperInstallerExecutionGate.BlockReason)
        case rootInstallerUnavailable
    }

    let signingKeys: [HelperReleaseSigningKey]
    let signatureChecker: HelperReleaseSignatureChecking
    let rootInstaller: HelperRootInstallerExecuting
    let trustedProvisioningStore: HelperTrustedProvisioningStore?
    let gate: HelperInstallerExecutionGate

    init(signingKeys: [HelperReleaseSigningKey] = HelperReleaseTrustAnchors.keys,
         signatureChecker: HelperReleaseSignatureChecking = HelperEd25519SignatureChecker(),
         rootInstaller: HelperRootInstallerExecuting = HelperUnavailableRootInstaller(),
         trustedProvisioningStore: HelperTrustedProvisioningStore? = nil,
         gate: HelperInstallerExecutionGate = HelperInstallerExecutionGate()) {
        self.signingKeys = signingKeys
        self.signatureChecker = signatureChecker
        self.rootInstaller = rootInstaller
        self.trustedProvisioningStore = trustedProvisioningStore
        self.gate = gate
    }

    /// Verifies a complete signed release hand-off without creating files, writing Keychain,
    /// touching launchd, or changing the installed Helper.
    func prepare(plan: HelperInstallerTransactionPlan,
                 provisioningEnvelopeData: Data,
                 artifacts: [String: Data],
                 expectedDigests: [HelperInstallerArtifactDigest]) throws -> HelperPreparedRootInstall {
        guard plan.action == .install || plan.action == .upgrade || plan.action == .repin else {
            throw Failure.unsupportedAction
        }
        guard HelperPolicy.isAbsoluteCleanPath(plan.jbRootPath), plan.jbRootPath != "/" else {
            throw Failure.rootMismatch
        }
        guard let envelope = try? JSONDecoder().decode(HelperSignedProvisioningManifest.self,
                                                       from: provisioningEnvelopeData) else {
            throw Failure.provisioningEnvelopeInvalid
        }
        let verifier = HelperProvisioningSignatureVerifier(keys: signingKeys, checker: signatureChecker)
        do {
            try verifier.verify(envelope)
            try envelope.payload.validate()
        } catch {
            throw Failure.provisioningEnvelopeInvalid
        }
        let bundle = envelope.payload
        guard bundle.jbRootPath == plan.jbRootPath else { throw Failure.rootMismatch }
        let verified: HelperRootReleaseSet.Verified
        do {
            verified = try HelperRootReleaseSet().verify(bundle: bundle, artifacts: artifacts,
                                                         expectedDigests: expectedDigests)
        } catch {
            throw Failure.releaseVerificationFailed
        }
        guard verified.releaseIdentifier == bundle.releaseIdentifier,
              verified.generation == bundle.generation else { throw Failure.provisioningMismatch }
        let journal: HelperInstallerTransactionJournal
        do {
            journal = try HelperInstallerTransactionJournal(action: plan.action,
                releaseIdentifier: verified.releaseIdentifier, generation: verified.generation)
            try journal.validateChain()
        } catch {
            throw Failure.journalCreationFailed
        }
        return HelperPreparedRootInstall(plan: plan, release: verified,
            provisioningEnvelopeSHA256: SHA256Digest.hex(provisioningEnvelopeData),
            provisioningEnvelopeData: provisioningEnvelopeData, initialJournal: journal)
    }

    /// This is the only execution entry point. It shares the same persistent lock inode as
    /// Helper startup acceptance, so a future adapter cannot race startup/repin acceptance.
    /// In this release every generated plan has executionEnabled == false and the default
    /// adapter is unavailable; therefore this method cannot perform a production write.
    func execute(_ prepared: HelperPreparedRootInstall, operatorApproved: Bool) throws {
        let evidence = HelperInstallerExecutionGate.Evidence(
            rootInstallerAvailable: rootInstaller.isProductionReady && trustedProvisioningStore != nil,
            releaseProvenanceVerified: HelperPolicy.isValidHash(prepared.provisioningEnvelopeSHA256),
            signedArtifactsVerified: Set(prepared.release.hashes.keys) == Set(HelperRootReleaseSet.Artifact.allCases),
            operatorApproved: operatorApproved)
        if let reason = gate.blockReason(plan: prepared.plan, evidence: evidence) {
            throw Failure.executionBlocked(reason)
        }
        guard rootInstaller.isProductionReady else { throw Failure.rootInstallerUnavailable }
        do {
            try HelperReleaseAcceptanceLock.withLock(root: prepared.plan.jbRootPath) {
                guard let trustedProvisioningStore else { throw Failure.rootInstallerUnavailable }
                try rootInstaller.execute(prepared) {
                    do {
                        try commitProvisioningConsistently(prepared, using: trustedProvisioningStore)
                        return .committed
                    } catch Failure.provisioningCommitRejected {
                        return .rejected
                    } catch Failure.provisioningCommitIndeterminate {
                        return .indeterminate
                    }
                }
            }
        } catch let failure as Failure {
            throw failure
        } catch {
            // Lock acquisition, unsafe lock metadata, or adapter failures are all fail-closed.
            throw Failure.rootInstallerUnavailable
        }
    }

    /// Reconciles R8's pending marker/checkpoint if commit reports an I/O error. The adapter can
    /// safely roll back only when the previous baseline is still authoritative. If the store
    /// cannot prove either side, the transaction is explicitly indeterminate and must not guess.
    private func commitProvisioningConsistently(_ prepared: HelperPreparedRootInstall,
                                                using store: HelperTrustedProvisioningStore) throws {
        do {
            _ = try store.commit(prepared.provisioningEnvelopeData, action: prepared.plan.action)
        } catch {
            do {
                try store.recoverPendingTransaction()
                let recovered = try store.loadTrustedBaseline()
                guard recovered.envelopeSHA256 == prepared.provisioningEnvelopeSHA256 else {
                    throw Failure.provisioningCommitRejected
                }
            } catch let failure as Failure {
                throw failure
            } catch HelperTrustedProvisioningStore.Failure.noTrustedBaseline where prepared.plan.action == .install {
                throw Failure.provisioningCommitRejected
            } catch {
                throw Failure.provisioningCommitIndeterminate
            }
        }
    }

}
