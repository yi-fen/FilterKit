import Foundation

/// Read-only startup gate for legacy, three-file deployment, and two-file association journals.
/// Inspection never mutates TweakInject; a pending or invalid journal blocks normal IPC service.
struct HelperStartupRecoveryCheck {
    enum Detail: Equatable {
        case clean
        case legacyRecoveryRequired
        case threeFileRecoveryRequired
        case bothRecoveryRequired
        case associationTransactionRecoveryRequired
        case invalidJournal
    }
    enum Result: Equatable { case clean, recoveryRequired, invalidJournal }

    func inspectDetailed(pluginDirectory: String, deploymentLedgerStore: HelperDeploymentDurableLedgerStore? = nil) -> Detail {
        do {
            let legacyStore = try HelperTransactionJournalStore(directoryPath: pluginDirectory)
            let legacyPending: Bool
            if let journal = try legacyStore.load() {
                try journal.validate()
                legacyPending = true
            } else {
                legacyPending = false
            }
            let threeFileExecutor = try HelperThreeFileTransactionExecutor(directoryPath: pluginDirectory)
            let threeFileEvidence = try threeFileExecutor.inspectPendingEvidence()
            let threeFilePending = threeFileEvidence != nil
            if let deploymentLedgerStore, let evidence = threeFileEvidence {
                guard let binding = evidence.deploymentBinding, evidence.validateAuxiliaryArtifacts() else { return .invalidJournal }
                let records = try deploymentLedgerStore.load()
                guard let record = records.first(where: { $0.batchID == binding.batchID }),
                      record.state != .completed || evidence.phase == .committed else { return .invalidJournal }
                let verdict = HelperDeploymentJournalReconciliation.compare(ledger: record, transaction: binding,
                    actualHashes: (evidence.actualHashes.0, evidence.actualHashes.1, evidence.actualHashes.2),
                    previousHashes: (evidence.previousHashes.0, evidence.previousHashes.1, evidence.previousHashes.2),
                    committed: evidence.phase == .committed)
                guard verdict == .matched || verdict == .artifactsConsistentPending else { return .invalidJournal }
            }
            let associationPending = try HelperPluginFilterConfigurationTransaction(directoryPath: pluginDirectory)
                .inspectPendingJournal()
            if associationPending { return .associationTransactionRecoveryRequired }
            switch (legacyPending, threeFilePending) {
            case (false, false): return .clean
            case (true, false): return .legacyRecoveryRequired
            case (false, true): return .threeFileRecoveryRequired
            case (true, true): return .bothRecoveryRequired
            }
        } catch {
            return .invalidJournal
        }
    }

    func inspect(pluginDirectory: String) -> Result {
        switch inspectDetailed(pluginDirectory: pluginDirectory) {
        case .clean: return .clean
        case .legacyRecoveryRequired, .threeFileRecoveryRequired, .bothRecoveryRequired, .associationTransactionRecoveryRequired: return .recoveryRequired
        case .invalidJournal: return .invalidJournal
        }
    }
}

/// Short-lived capability minted only for an authenticated, non-root FilterKit maintenance
/// client. The Helper itself performs the privileged operation. The UI confirmation bit is an
/// intent signal, not cryptographic proof of a human gesture; peer trust comes from the existing
/// code-identity policy plus kernel socket/Audit Token/PID-generation binding.
struct HelperRecoveryAuthorization: Equatable {
    let transactionID: UUID
    let requestNonce: UUID
    let authorizedAt: Date
    let peer: HelperPeerIdentity
    private init(transactionID: UUID, requestNonce: UUID, authorizedAt: Date, peer: HelperPeerIdentity) {
        self.transactionID = transactionID
        self.requestNonce = requestNonce
        self.authorizedAt = authorizedAt
        self.peer = peer
    }

    enum AuthorizationError: Error, Equatable { case confirmationRequired, invalidNonce, peerMustBeUnprivileged, identityMismatch, incompleteKernelEvidence }

    static func authorize(context: HelperAuthenticatedPeerContext, transactionID: UUID,
                          requestNonce: UUID, operatorConfirmed: Bool,
                          now: Date = Date(), clockSkewLimit: TimeInterval = 120) throws -> HelperRecoveryAuthorization {
        guard operatorConfirmed else { throw AuthorizationError.confirmationRequired }
        guard requestNonce != UUID(uuidString: "00000000-0000-0000-0000-000000000000"),
              transactionID != UUID(uuidString: "00000000-0000-0000-0000-000000000000") else {
            throw AuthorizationError.invalidNonce
        }
        guard abs(now.timeIntervalSince(context.authenticatedAt)) <= max(1, clockSkewLimit) else {
            throw AuthorizationError.identityMismatch
        }
        // The desktop/mobile app is intentionally unprivileged. Requiring UID 0 here made
        // maintenance impossible for the actual App -> root Helper architecture.
        guard context.peer.uid != 0, context.identity.uid != 0 else {
            throw AuthorizationError.peerMustBeUnprivileged
        }
        guard context.peer.uid == context.identity.uid, context.peer.gid == context.identity.gid,
              context.peer.pid == context.identity.pid, context.identity.pid > 0,
              context.sessionNonce.range(of: "^[0-9a-fA-F]{32,}$", options: .regularExpression) != nil,
              context.identity.cdHashHex.range(of: "^[0-9a-fA-F]{40}$", options: .regularExpression) != nil else {
            throw AuthorizationError.identityMismatch
        }
        guard HelperPeerIdentityBindingPolicy.hasCompleteDarwinProcessGenerationEvidence(context.identity) else {
            throw AuthorizationError.incompleteKernelEvidence
        }
        return HelperRecoveryAuthorization(transactionID: transactionID, requestNonce: requestNonce,
            authorizedAt: now, peer: context.identity)
    }
}

/// Explicit recovery entry point. Startup remains inspection-only. Recovery requires a
/// transaction-scoped capability, exact Ledger/Journal identity match, and post-recovery
/// verification before the durable ledger is finalized.
struct HelperAuthorizedRecoveryCoordinator {
    enum RecoveryError: Error, Equatable {
        case notRoot
        case authorizationMissing
        case legacyRecoveryRequiresDedicatedWorkflow
        case invalidJournal
        case ledgerUnavailable
        case transactionIdentityMismatch
        case recoveryIncomplete
        case ledgerFinalizationFailed
        case auditUnavailable
        case authorizationExpired
    }

    private let audit: HelperAuditSink
    init(audit: HelperAuditSink) { self.audit = audit }

    @discardableResult
    func reconcileThreeFileTransaction(pluginDirectory: String,
                                        ledgerStore: HelperDeploymentDurableLedgerStore,
                                        authorization: HelperRecoveryAuthorization) throws -> HelperDeploymentDurableLedgerStore.RecoveryFinalization? {
        // This coordinator runs inside the privileged Helper. The authenticated IPC peer
        // is expected to be the unprivileged App; do not confuse peer UID with Helper euid.
        guard geteuid() == 0 else { throw RecoveryError.notRoot }
        guard authorization.peer.uid != 0,
              authorization.requestNonce != UUID(uuidString: "00000000-0000-0000-0000-000000000000") else {
            throw RecoveryError.authorizationMissing
        }
        guard abs(Date().timeIntervalSince(authorization.authorizedAt)) <= 120 else {
            throw RecoveryError.authorizationExpired
        }
        let executor = try HelperThreeFileTransactionExecutor(directoryPath: pluginDirectory)
        guard let evidence = try executor.inspectPendingEvidence(),
              evidence.transactionID == authorization.transactionID,
              let binding = evidence.deploymentBinding, binding.validate(),
              binding.transactionID == authorization.transactionID else { throw RecoveryError.invalidJournal }

        let records: [HelperDeploymentDurableLedgerStore.Record]
        do { records = try ledgerStore.load() } catch { throw RecoveryError.ledgerUnavailable }
        guard let record = records.first(where: { $0.batchID == binding.batchID }) else {
            throw RecoveryError.ledgerUnavailable
        }
        let verdict = HelperDeploymentJournalReconciliation.compare(
            ledger: record, transaction: binding,
            actualHashes: (evidence.actualHashes.0, evidence.actualHashes.1, evidence.actualHashes.2),
            previousHashes: (evidence.previousHashes.0, evidence.previousHashes.1, evidence.previousHashes.2),
            committed: evidence.phase == .committed)
        guard verdict == .matched || verdict == .artifactsConsistentPending,
              evidence.validateAuxiliaryArtifacts() else { throw RecoveryError.transactionIdentityMismatch }
        if evidence.phase == .committed && verdict != .matched { throw RecoveryError.transactionIdentityMismatch }

        do {
            try audit.append(HelperAuditRecord(requestID: authorization.requestNonce, peer: authorization.peer,
                outcome: .accepted, reasonCode: "transaction_recovery_started"))
        } catch { throw RecoveryError.auditUnavailable }

        let disposition: HelperThreeFileTransactionExecutor.RecoveryDisposition
        do { disposition = try executor.reconcile(expectedTransactionID: authorization.transactionID,
                                                   preserveJournal: true) }
        catch { throw RecoveryError.recoveryIncomplete }

        let finalization: HelperDeploymentDurableLedgerStore.RecoveryFinalization =
            disposition == .committed ? .committed : .rolledBack
        // Ledger terminal state is persisted while the transaction journal is still present.
        // A crash before journal removal leaves enough evidence for an idempotent retry.
        do { try ledgerStore.finalizeRecovered(binding: binding, disposition: finalization) }
        catch { throw RecoveryError.ledgerFinalizationFailed }
        do { try executor.clearReconciledJournal(expectedTransactionID: authorization.transactionID) }
        catch { throw RecoveryError.recoveryIncomplete }
        guard HelperStartupRecoveryCheck().inspectDetailed(pluginDirectory: pluginDirectory,
              deploymentLedgerStore: ledgerStore) == .clean else { throw RecoveryError.recoveryIncomplete }
        try? audit.append(HelperAuditRecord(requestID: authorization.requestNonce, peer: authorization.peer,
            outcome: .succeeded, reasonCode: finalization == .committed ? "transaction_recovery_committed" : "transaction_recovery_rolled_back"))
        return finalization
    }
}
