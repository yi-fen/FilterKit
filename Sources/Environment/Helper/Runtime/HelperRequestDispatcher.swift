import Foundation

/// Central Helper request gate. It owns request freshness, session binding, replay protection,
/// payload decoding, release checks, and request-level audit decisions. P1-25 deliberately keeps
/// operation execution disabled; this dispatcher is the single future insertion point for the
/// verified ownership/deployment pipeline.
final class HelperRequestDispatcher {
    static let executionReleased = false
    /// Association writes remain independently locked pending RootHide device validation.
    static let pluginAssociationCommitReleased = false
    /// Uninstall IPC is integrated but remains fail-closed pending signed release and device acceptance.
    static let pluginUninstallExecutionReleased = false

    enum RejectionCode: String, Codable {
        case invalidSession = "invalid_session"
        case staleRequest = "stale_request"
        case replayedRequest = "replayed_request"
        case deploymentBatchInProgress = "deployment_batch_in_progress"
        case deploymentBatchOutcomeUnknown = "deployment_batch_outcome_unknown"
        case deploymentBatchRolledBack = "deployment_batch_rolled_back"
        case deploymentBatchConflict = "deployment_batch_id_conflict"
        case malformedOperation = "malformed_operation"
        case malformedBatch = "malformed_batch"
        case executionDisabled = "execution_disabled"
        case dispatchNotConfigured = "dispatch_not_configured"
        case authorizationFailed = "authorization_failed"
        case deploymentFailed = "deployment_failed"
        case auditUnavailable = "audit_unavailable"
        case maintenanceRecoveryNotReleased = "maintenance_recovery_not_released"
        case recoveryRequired = "recovery_required"
        case invalidTransactionJournal = "invalid_transaction_journal"
        case messageNotAllowed = "message_not_allowed"
        case malformedPluginMutation = "malformed_plugin_mutation"
        case pluginMutationAuthorizationFailed = "plugin_mutation_authorization_failed"
        case pluginMutationRecoveryRequired = "plugin_mutation_recovery_required"
        case pluginMutationAuditUnavailable = "plugin_mutation_audit_unavailable"
        case malformedIdentityAttestation = "malformed_identity_attestation"
        case malformedAppPluginActivation = "malformed_app_plugin_activation"
        case appPluginActivationAuthorizationFailed = "app_plugin_activation_authorization_failed"
        case appPluginActivationLedgerUnavailable = "app_plugin_activation_ledger_unavailable"
        case appPluginActivationTransactionConflict = "app_plugin_activation_transaction_conflict"
        case identityAttestationUnavailable = "identity_attestation_unavailable"
        case malformedPluginUninstall = "malformed_plugin_uninstall"
        case pluginUninstallAuthorizationFailed = "plugin_uninstall_authorization_failed"
        case pluginUninstallRecoveryRequired = "plugin_uninstall_recovery_required"
        case pluginUninstallAuditUnavailable = "plugin_uninstall_audit_unavailable"
    }

    struct Rejection: Codable, Equatable {
        let code: RejectionCode
        let message: String
    }

    /// The Helper serves one shared plugin-directory Journal. Serialize dispatcher work so
    /// two concurrent requests cannot both pass the clean-recovery check and race that Journal.
    private let dispatchSerializationLock = NSRecursiveLock()
    private let manifest: HelperDeploymentManifest
    private let audit: HelperAuditSink
    private let replayGuard: HelperRequestReplayGuard
    private let deploymentIdempotencyLedger: HelperDeploymentIdempotencyLedger
    private let deploymentLedgerStore: HelperDeploymentDurableLedgerStore?
    private let clockSkewLimit: TimeInterval
    private let deploymentPipeline: HelperDeploymentPipeline?
    private let pluginDirectory: String?
    private let pluginFilterMutationAuthorizer: HelperPluginFilterMutationAuthorizer?
    private let pluginAssociationTransaction: HelperPluginFilterConfigurationTransaction?
    private let pluginIdentityAttestor: HelperPluginIdentityAttestor?
    private let pluginUninstallAuthorizer: HelperPluginUninstallAuthorizer?
    private let pluginUninstallTransaction: HelperThreeFileUninstallTransaction?
    private let activationTransactionLedgerStore: HelperAppPluginActivationTransactionLedgerStore?
    /// Test-injectable only; production construction leaves activation writes disabled.
    private let activationCommitExecutionEnabled: Bool

    init(manifest: HelperDeploymentManifest,
         audit: HelperAuditSink,
         replayGuard: HelperRequestReplayGuard = HelperRequestReplayGuard(),
         deploymentIdempotencyLedger: HelperDeploymentIdempotencyLedger = HelperDeploymentIdempotencyLedger(),
         deploymentLedgerStore: HelperDeploymentDurableLedgerStore? = nil,
         clockSkewLimit: TimeInterval = 120,
         deploymentPipeline: HelperDeploymentPipeline? = nil,
         pluginDirectory: String? = nil,
         pluginFilterMutationAuthorizer: HelperPluginFilterMutationAuthorizer? = nil,
         pluginAssociationTransaction: HelperPluginFilterConfigurationTransaction? = nil,
         pluginIdentityAttestor: HelperPluginIdentityAttestor? = nil,
         pluginUninstallAuthorizer: HelperPluginUninstallAuthorizer? = nil,
         pluginUninstallTransaction: HelperThreeFileUninstallTransaction? = nil,
         activationTransactionLedgerStore: HelperAppPluginActivationTransactionLedgerStore? = nil,
         activationCommitExecutionEnabled: Bool = false) {
        self.manifest = manifest
        self.audit = audit
        self.replayGuard = replayGuard
        self.deploymentIdempotencyLedger = deploymentIdempotencyLedger
        self.deploymentLedgerStore = deploymentLedgerStore
        self.clockSkewLimit = max(1, clockSkewLimit)
        self.deploymentPipeline = deploymentPipeline
        self.pluginDirectory = pluginDirectory
        self.pluginFilterMutationAuthorizer = pluginFilterMutationAuthorizer
        self.pluginAssociationTransaction = pluginAssociationTransaction
        self.pluginIdentityAttestor = pluginIdentityAttestor
        self.pluginUninstallAuthorizer = pluginUninstallAuthorizer
        self.pluginUninstallTransaction = pluginUninstallTransaction
        self.activationTransactionLedgerStore = activationTransactionLedgerStore
        self.activationCommitExecutionEnabled = activationCommitExecutionEnabled
    }

    func dispatch(_ envelope: HelperIPCEnvelope,
                  context: HelperAuthenticatedPeerContext,
                  now: Date = Date()) -> HelperIPCEnvelope {
        dispatchSerializationLock.lock(); defer { dispatchSerializationLock.unlock() }
        guard envelope.protocolVersion == HelperIPCEnvelope.currentVersion,
              let nonce = envelope.nonce, nonce == context.sessionNonce,
              context.peer.uid == context.identity.uid,
              context.peer.gid == context.identity.gid,
              context.peer.pid == context.identity.pid,
              context.identity.pid > 0,
              abs(now.timeIntervalSince(context.authenticatedAt)) <= clockSkewLimit else {
            return reject(envelope, code: .invalidSession, operation: nil, peer: context.identity)
        }
        guard abs(now.timeIntervalSince(envelope.createdAt)) <= clockSkewLimit else {
            return reject(envelope, code: .staleRequest, operation: nil, peer: context.identity)
        }
        if envelope.messageType != .deploymentBatchRequest {
            guard replayGuard.accept(envelope.requestID, now: now) else {
                return reject(envelope, code: .replayedRequest, operation: nil, peer: context.identity)
            }
        }

        switch envelope.messageType {
        case .healthRequest:
            do {
                try audit.append(HelperAuditRecord(requestID: envelope.requestID, peer: context.identity,
                    outcome: .accepted, reasonCode: "health_check"))
            } catch {
                return reject(envelope, code: .auditUnavailable, operation: nil, peer: context.identity)
            }
            let status = recoveryStatus()
            let response = HelperStatusResponse(helperReachable: true, recoveryStatus: status,
                                                checkedAt: now, protocolVersion: HelperIPCEnvelope.currentVersion)
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            return HelperIPCEnvelope(messageType: .healthResponse, requestID: envelope.requestID,
                                     createdAt: now, nonce: context.sessionNonce,
                                     payload: try? encoder.encode(response))

        case .maintenanceRecoveryRequest:
            guard let payload = envelope.payload,
                  let request = Self.decodeMaintenanceRequest(payload),
                  request.requestNonce == envelope.requestID,
                  request.requestNonce != UUID(uuidString: "00000000-0000-0000-0000-000000000000"),
                  abs(request.requestedAt.timeIntervalSince(envelope.createdAt)) <= 5,
                  abs(now.timeIntervalSince(request.requestedAt)) <= clockSkewLimit else {
                return reject(envelope, code: .malformedOperation, operation: nil, peer: context.identity)
            }
            let currentStatus = recoveryStatus()
            let result: HelperMaintenanceResult
            var boundTransactionID: UUID? = nil
            switch request.action {
            case .inspect:
                result = .inspected
            case .reconcileThreeFileTransaction:
                guard request.operatorConfirmed,
                      let transactionID = request.transactionID,
                      transactionID != UUID(uuidString: "00000000-0000-0000-0000-000000000000") else {
                    return reject(envelope, code: .malformedOperation, operation: nil, peer: context.identity)
                }
                do {
                    _ = try HelperRecoveryAuthorization.authorize(context: context,
                        transactionID: transactionID, requestNonce: request.requestNonce,
                        operatorConfirmed: request.operatorConfirmed, now: now,
                        clockSkewLimit: clockSkewLimit)
                    boundTransactionID = transactionID
                    // Authorization is integrated end-to-end, but recovery mutation remains
                    // disabled pending Darwin/Xcode and RootHide device validation.
                    result = .recoveryNotReleased
                } catch {
                    return reject(envelope, code: .malformedOperation, operation: nil, peer: context.identity)
                }
            }
            do {
                try audit.append(HelperAuditRecord(requestID: envelope.requestID, peer: context.identity,
                    outcome: request.action == .inspect ? .accepted : .rejected,
                    reasonCode: request.action == .inspect ? "maintenance_inspect" :
                        (boundTransactionID == nil ? "maintenance_authorization_rejected" : RejectionCode.maintenanceRecoveryNotReleased.rawValue)))
            } catch {
                return reject(envelope, code: .auditUnavailable, operation: nil, peer: context.identity)
            }
            let response = HelperMaintenanceRecoveryResponse(result: result, recoveryStatus: currentStatus,
                completedAt: now, transactionID: boundTransactionID)
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            return HelperIPCEnvelope(messageType: .maintenanceRecoveryResponse, requestID: envelope.requestID,
                                     createdAt: now, nonce: context.sessionNonce,
                                     payload: try? encoder.encode(response))

        case .pluginIdentityAttestationRequest:
            guard let payload = envelope.payload,
                  let request = Self.decodePluginIdentityAttestation(payload),
                  request.requestID == envelope.requestID,
                  abs(request.createdAt.timeIntervalSince(envelope.createdAt)) <= 5,
                  request.validate(now: now, clockSkewLimit: clockSkewLimit) else {
                return reject(envelope, code: .malformedIdentityAttestation, operation: nil, peer: context.identity)
            }
            guard recoveryStatus() == .clean,
                  let attestor = pluginIdentityAttestor else {
                return reject(envelope, code: .identityAttestationUnavailable, operation: nil, peer: context.identity)
            }
            let attestation = attestor.attest(request, now: now)
            do {
                try audit.append(HelperAuditRecord(requestID: envelope.requestID, peer: context.identity,
                    outcome: attestation.isVerified ? .accepted : .rejected,
                    reasonCode: "plugin_identity_attestation.\(attestation.reasonCode ?? "unknown")"))
            } catch {
                return reject(envelope, code: .auditUnavailable, operation: nil, peer: context.identity)
            }
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            guard let data = try? encoder.encode(attestation) else {
                return reject(envelope, code: .malformedIdentityAttestation, operation: nil, peer: context.identity)
            }
            return HelperIPCEnvelope(messageType: .pluginIdentityAttestationResponse,
                requestID: envelope.requestID, createdAt: now, nonce: context.sessionNonce, payload: data)

        case .appPluginActivationTransactionQueryRequest:
            guard let payload = envelope.payload,
                  let query = Self.decodeAppPluginActivationTransactionQuery(payload),
                  query.requestID == envelope.requestID,
                  abs(query.createdAt.timeIntervalSince(envelope.createdAt)) <= 5,
                  query.validate(now: now, clockSkewLimit: clockSkewLimit) else {
                return reject(envelope, code: .malformedAppPluginActivation, operation: nil, peer: context.identity)
            }
            guard let ledger = activationTransactionLedgerStore else {
                return reject(envelope, code: .appPluginActivationLedgerUnavailable, operation: nil, peer: context.identity)
            }
            do {
                // A status query is strictly read-only. It never resolves Ledger state or
                // removes transaction artifacts; explicit reconciliation has its own request.
                let record = try ledger.record(commandRequestID: query.commandRequestID,
                    pluginID: query.pluginID, targetBundleIdentifier: query.targetBundleIdentifier)
                let status = Self.makeActivationTransactionStatus(query: query, record: record, checkedAt: now)
                guard status.matches(query) else {
                    return reject(envelope, code: .appPluginActivationTransactionConflict, operation: nil, peer: context.identity)
                }
                let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
                guard let data = try? encoder.encode(status) else {
                    return reject(envelope, code: .malformedAppPluginActivation, operation: nil, peer: context.identity)
                }
                try audit.append(HelperAuditRecord(requestID: envelope.requestID, peer: context.identity,
                    outcome: .accepted, reasonCode: record == nil ? "app_plugin_activation_transaction_not_found" : "app_plugin_activation_transaction_queried"))
                return HelperIPCEnvelope(messageType: .appPluginActivationTransactionStatusResponse,
                    requestID: envelope.requestID, createdAt: now, nonce: context.sessionNonce, payload: data)
            } catch {
                return reject(envelope, code: .appPluginActivationLedgerUnavailable, operation: nil, peer: context.identity)
            }

        case .appPluginActivationTransactionReconcileRequest:
            guard let payload = envelope.payload,
                  let request = Self.decodeAppPluginActivationTransactionReconciliationRequest(payload),
                  request.requestID == envelope.requestID,
                  abs(request.createdAt.timeIntervalSince(envelope.createdAt)) <= 5,
                  request.validate(now: now, clockSkewLimit: clockSkewLimit) else {
                return reject(envelope, code: .malformedAppPluginActivation, operation: nil, peer: context.identity)
            }
            guard let ledger = activationTransactionLedgerStore,
                  let transaction = pluginAssociationTransaction else {
                return reject(envelope, code: .appPluginActivationLedgerUnavailable, operation: nil, peer: context.identity)
            }
            do {
                var record = try ledger.record(commandRequestID: request.commandRequestID,
                    pluginID: request.pluginID, targetBundleIdentifier: request.targetBundleIdentifier)
                if let current = record, current.state == .outcomeUnknown {
                    let evidence = try transaction.inspectActivationEvidence(
                        transactionID: current.transactionID, pluginID: current.pluginID,
                        oldPlistSHA256: current.filterBeforeSHA256,
                        oldManifestSHA256: current.manifestBeforeSHA256,
                        newPlistSHA256: current.filterAfterSHA256,
                        newManifestSHA256: current.manifestAfterSHA256)
                    if let evidence, evidence.transactionID == current.transactionID,
                       evidence.pluginID == current.pluginID, evidence.disposition != .unknown,
                       let observedPlist = evidence.observedPlistSHA256,
                       let observedManifest = evidence.observedManifestSHA256 {
                        record = try ledger.resolveUnknown(commandRequestID: current.commandRequestID,
                            transactionID: current.transactionID, pluginID: current.pluginID,
                            targetBundleIdentifier: current.targetBundleIdentifier,
                            disposition: evidence.disposition, observedPlistSHA256: observedPlist,
                            observedManifestSHA256: observedManifest, now: now)
                    }
                }
                // Ledger terminal state is persisted before journal cleanup. If cleanup fails
                // or Helper crashes here, a repeated explicit request safely retries cleanup only.
                if let terminal = record {
                    switch terminal.state {
                    case .committed:
                        try transaction.finalizeResolvedActivationJournal(
                            transactionID: terminal.transactionID, pluginID: terminal.pluginID,
                            disposition: .committed, plistSHA256: terminal.filterAfterSHA256,
                            manifestSHA256: terminal.manifestAfterSHA256)
                    case .rolledBack:
                        try transaction.finalizeResolvedActivationJournal(
                            transactionID: terminal.transactionID, pluginID: terminal.pluginID,
                            disposition: .rolledBack, plistSHA256: terminal.filterBeforeSHA256,
                            manifestSHA256: terminal.manifestBeforeSHA256)
                    case .executing, .outcomeUnknown: break
                    }
                }
                let query = request.statusQuery
                let status = Self.makeActivationTransactionStatus(query: query, record: record, checkedAt: now)
                guard status.matches(query) else {
                    return reject(envelope, code: .appPluginActivationTransactionConflict, operation: nil, peer: context.identity)
                }
                let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
                guard let data = try? encoder.encode(status) else {
                    return reject(envelope, code: .malformedAppPluginActivation, operation: nil, peer: context.identity)
                }
                try audit.append(HelperAuditRecord(requestID: envelope.requestID, peer: context.identity,
                    outcome: .accepted, reasonCode: "app_plugin_activation_transaction_reconciled"))
                return HelperIPCEnvelope(messageType: .appPluginActivationTransactionStatusResponse,
                    requestID: envelope.requestID, createdAt: now, nonce: context.sessionNonce, payload: data)
            } catch {
                return reject(envelope, code: .appPluginActivationLedgerUnavailable, operation: nil, peer: context.identity)
            }

        case .appPluginActivationPrepareRequest:
            guard let payload = envelope.payload,
                  let command = Self.decodeAppPluginActivationCommand(payload),
                  command.requestID == envelope.requestID,
                  abs(command.createdAt.timeIntervalSince(envelope.createdAt)) <= 5,
                  command.validate(now: now, clockSkewLimit: clockSkewLimit) else {
                return reject(envelope, code: .malformedAppPluginActivation, operation: nil, peer: context.identity)
            }
            guard recoveryStatus() == .clean else {
                return reject(envelope, code: .pluginMutationRecoveryRequired, operation: nil, peer: context.identity)
            }
            guard let authorizer = pluginFilterMutationAuthorizer else {
                return reject(envelope, code: .dispatchNotConfigured, operation: nil, peer: context.identity)
            }
            do {
                let prepared = try authorizer.prepare(command.makeMutationRequest(), now: now)
                guard let filterBefore = prepared.response.previousPlistSHA256,
                      let filterAfter = prepared.response.proposedPlistSHA256,
                      let manifestBefore = prepared.response.previousManifestSHA256,
                      let manifestAfter = prepared.response.proposedManifestSHA256 else {
                    return reject(envelope, code: .appPluginActivationAuthorizationFailed, operation: nil, peer: context.identity)
                }
                guard let currentManifest = try? JSONDecoder().decode(FilterKitPluginManifest.self,
                    from: prepared.previousManifestData),
                    let actualPreviousEnabled = HelperAppPluginActivationStateReader.enabledState(
                        in: currentManifest, targetBundleIdentifier: command.targetBundleIdentifier) else {
                    return reject(envelope, code: .appPluginActivationAuthorizationFailed, operation: nil, peer: context.identity)
                }
                guard actualPreviousEnabled == command.expectedEnabled else {
                    return reject(envelope, code: .appPluginActivationAuthorizationFailed, operation: nil, peer: context.identity)
                }
                let plan = HelperAppPluginActivationPlan(requestID: command.requestID,
                    pluginID: command.pluginID, targetBundleIdentifier: command.targetBundleIdentifier,
                    previousEnabled: actualPreviousEnabled, desiredEnabled: command.desiredEnabled,
                    filterBeforeSHA256: filterBefore, filterAfterSHA256: filterAfter,
                    manifestBeforeSHA256: manifestBefore, manifestAfterSHA256: manifestAfter,
                    changed: actualPreviousEnabled != command.desiredEnabled)
                guard plan.validates(command: command) else {
                    return reject(envelope, code: .appPluginActivationAuthorizationFailed, operation: nil, peer: context.identity)
                }
                do {
                    try audit.append(HelperAuditRecord(requestID: envelope.requestID, peer: context.identity,
                        outcome: .accepted, reasonCode: plan.changed ? "app_plugin_activation_prepared_read_only" : "app_plugin_activation_already_current"))
                } catch {
                    return reject(envelope, code: .pluginMutationAuditUnavailable, operation: nil, peer: context.identity)
                }
                let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
                return HelperIPCEnvelope(messageType: .appPluginActivationPrepared,
                    requestID: envelope.requestID, createdAt: now, nonce: context.sessionNonce,
                    payload: try? encoder.encode(plan))
            } catch {
                return reject(envelope, code: .appPluginActivationAuthorizationFailed, operation: nil, peer: context.identity)
            }

        case .appPluginActivationCommitRequest:
            guard let payload = envelope.payload,
                  let commit = Self.decodeAppPluginActivationCommit(payload),
                  commit.requestID == envelope.requestID,
                  abs(commit.createdAt.timeIntervalSince(envelope.createdAt)) <= 5,
                  commit.validates(now: now, clockSkewLimit: clockSkewLimit) else {
                return reject(envelope, code: .malformedAppPluginActivation, operation: nil, peer: context.identity)
            }
            let command = commit.command
            guard recoveryStatus() == .clean else {
                return reject(envelope, code: .pluginMutationRecoveryRequired, operation: nil, peer: context.identity)
            }
            guard let authorizer = pluginFilterMutationAuthorizer,
                  let transaction = pluginAssociationTransaction else {
                return reject(envelope, code: .dispatchNotConfigured, operation: nil, peer: context.identity)
            }
            do {
                // Re-read ownership, Manifest and Filter at the commit boundary. The supplied
                // Prepare plan is accepted only if every field matches this fresh Helper result.
                let prepared = try authorizer.prepare(command.makeMutationRequest(), now: now)
                guard let currentManifest = try? JSONDecoder().decode(FilterKitPluginManifest.self,
                    from: prepared.previousManifestData),
                    let actualEnabled = HelperAppPluginActivationStateReader.enabledState(
                        in: currentManifest, targetBundleIdentifier: command.targetBundleIdentifier) else {
                    return reject(envelope, code: .appPluginActivationAuthorizationFailed, operation: nil, peer: context.identity)
                }
                guard actualEnabled == command.expectedEnabled,
                      let filterBefore = prepared.response.previousPlistSHA256,
                      let filterAfter = prepared.response.proposedPlistSHA256,
                      let manifestBefore = prepared.response.previousManifestSHA256,
                      let manifestAfter = prepared.response.proposedManifestSHA256 else {
                    return reject(envelope, code: .appPluginActivationAuthorizationFailed, operation: nil, peer: context.identity)
                }
                let freshPlan = HelperAppPluginActivationPlan(requestID: command.requestID,
                    pluginID: command.pluginID, targetBundleIdentifier: command.targetBundleIdentifier,
                    previousEnabled: actualEnabled, desiredEnabled: command.desiredEnabled,
                    filterBeforeSHA256: filterBefore, filterAfterSHA256: filterAfter,
                    manifestBeforeSHA256: manifestBefore, manifestAfterSHA256: manifestAfter,
                    changed: actualEnabled != command.desiredEnabled)
                guard freshPlan == commit.preparedPlan,
                      freshPlan.validates(command: command) else {
                    return reject(envelope, code: .appPluginActivationAuthorizationFailed, operation: nil, peer: context.identity)
                }
                // Production remains fail-closed. The injectable switch is only for isolated
                // transaction/dispatcher tests and is never enabled by HelperRuntime.
                guard activationCommitExecutionEnabled else {
                    return reject(envelope, code: .executionDisabled, operation: nil, peer: context.identity)
                }
                guard let activationLedger = activationTransactionLedgerStore else {
                    return reject(envelope, code: .appPluginActivationLedgerUnavailable, operation: nil, peer: context.identity)
                }
                do {
                    if try activationLedger.record(commandRequestID: command.requestID,
                        pluginID: command.pluginID, targetBundleIdentifier: command.targetBundleIdentifier) != nil {
                        return reject(envelope, code: .appPluginActivationTransactionConflict, operation: nil, peer: context.identity)
                    }
                } catch {
                    return reject(envelope, code: .appPluginActivationLedgerUnavailable, operation: nil, peer: context.identity)
                }
                do {
                    try audit.append(HelperAuditRecord(requestID: envelope.requestID, peer: context.identity,
                        outcome: .accepted, reasonCode: "app_plugin_activation_commit_authorized"))
                } catch {
                    return reject(envelope, code: .pluginMutationAuditUnavailable, operation: nil, peer: context.identity)
                }
                let proof: HelperAppPluginActivationProof
                if prepared.disposition == .alreadyInRequestedState {
                    proof = HelperAppPluginActivationProof(requestID: command.requestID,
                        pluginID: command.pluginID, targetBundleIdentifier: command.targetBundleIdentifier,
                        enabled: command.desiredEnabled, filterSHA256: filterBefore,
                        manifestSHA256: manifestBefore, transactionID: nil, completedAt: now)
                } else {
                    let transactionID = UUID()
                    let ledgerRecord = try HelperAppPluginActivationTransactionRecord(
                        command: command, plan: freshPlan, transactionID: transactionID)
                    try activationLedger.insertExecuting(ledgerRecord)
                    do {
                        let receipt = try transaction.execute(prepared, transactionID: transactionID,
                            retainJournalForOutcomeReconciliation: true)
                        guard receipt.transactionID == transactionID else {
                            _ = try activationLedger.transition(commandRequestID: command.requestID,
                                pluginID: command.pluginID, targetBundleIdentifier: command.targetBundleIdentifier,
                                to: .outcomeUnknown)
                            return reject(envelope, code: .appPluginActivationTransactionConflict, operation: nil, peer: context.identity)
                        }
                        _ = try activationLedger.transition(commandRequestID: command.requestID,
                            pluginID: command.pluginID, targetBundleIdentifier: command.targetBundleIdentifier,
                            to: .committed, now: receipt.completedAt)
                        // The durable ledger is authoritative before journal cleanup. If cleanup
                        // fails, retain the committed journal for startup recovery inspection.
                        try? transaction.finalizeCommittedActivationJournal(transactionID: transactionID,
                            pluginID: command.pluginID, plistSHA256: receipt.plistSHA256,
                            manifestSHA256: receipt.manifestSHA256)
                        proof = HelperAppPluginActivationProof(requestID: command.requestID,
                            pluginID: command.pluginID, targetBundleIdentifier: command.targetBundleIdentifier,
                            enabled: command.desiredEnabled, filterSHA256: receipt.plistSHA256,
                            manifestSHA256: receipt.manifestSHA256, transactionID: receipt.transactionID,
                            completedAt: receipt.completedAt)
                    } catch {
                        // A thrown transaction may have crashed between file replacement and
                        // reconciliation. Preserve ambiguity; never claim rollback without proof.
                        _ = try? activationLedger.transition(commandRequestID: command.requestID,
                            pluginID: command.pluginID, targetBundleIdentifier: command.targetBundleIdentifier,
                            to: .outcomeUnknown)
                        throw error
                    }
                }
                guard proof.validates(command: command, now: Date(), maximumAge: 125) else {
                    // A committed transaction must never be misreported as a successful IPC proof.
                    return reject(envelope, code: .appPluginActivationAuthorizationFailed, operation: nil, peer: context.identity)
                }
                let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
                let responseData = try encoder.encode(proof)
                try? audit.append(HelperAuditRecord(requestID: envelope.requestID, peer: context.identity,
                    outcome: .accepted, reasonCode: proof.transactionID == nil
                        ? "app_plugin_activation_already_current" : "app_plugin_activation_committed"))
                return HelperIPCEnvelope(messageType: .appPluginActivationCommitted,
                    requestID: envelope.requestID, createdAt: now, nonce: context.sessionNonce,
                    payload: responseData)
            } catch {
                return reject(envelope, code: .appPluginActivationAuthorizationFailed, operation: nil, peer: context.identity)
            }

        case .pluginFilterMutationPrepareRequest:
            guard let payload = envelope.payload,
                  let request = Self.decodePluginFilterMutation(payload),
                  request.requestID == envelope.requestID,
                  abs(request.createdAt.timeIntervalSince(envelope.createdAt)) <= 5,
                  request.validateShape(now: now, clockSkewLimit: clockSkewLimit) else {
                return reject(envelope, code: .malformedPluginMutation, operation: nil, peer: context.identity)
            }
            guard recoveryStatus() == .clean else {
                return reject(envelope, code: .pluginMutationRecoveryRequired, operation: nil, peer: context.identity)
            }
            guard let authorizer = pluginFilterMutationAuthorizer else {
                return reject(envelope, code: .dispatchNotConfigured, operation: nil, peer: context.identity)
            }
            do {
                let prepared = try authorizer.prepare(request, now: now)
                let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
                let responseData = try encoder.encode(prepared.response)
                do {
                    try audit.append(HelperAuditRecord(requestID: envelope.requestID, peer: context.identity,
                        outcome: .accepted, reasonCode: prepared.disposition == .alreadyInRequestedState
                            ? "plugin_mutation_already_current" : "plugin_mutation_prepared_read_only"))
                } catch {
                    return reject(envelope, code: .pluginMutationAuditUnavailable, operation: nil, peer: context.identity)
                }
                return HelperIPCEnvelope(messageType: .pluginFilterMutationPrepared, requestID: envelope.requestID,
                    createdAt: now, nonce: context.sessionNonce, payload: responseData)
            } catch {
                return reject(envelope, code: .pluginMutationAuthorizationFailed, operation: nil, peer: context.identity)
            }

        case .pluginFilterMutationCommitRequest:
            guard let payload = envelope.payload,
                  let request = Self.decodePluginFilterMutation(payload),
                  request.requestID == envelope.requestID,
                  abs(request.createdAt.timeIntervalSince(envelope.createdAt)) <= 5,
                  request.validateShape(now: now, clockSkewLimit: clockSkewLimit) else {
                return reject(envelope, code: .malformedPluginMutation, operation: nil, peer: context.identity)
            }
            guard recoveryStatus() == .clean else {
                return reject(envelope, code: .pluginMutationRecoveryRequired, operation: nil, peer: context.identity)
            }
            guard Self.pluginAssociationCommitReleased else {
                return reject(envelope, code: .executionDisabled, operation: nil, peer: context.identity)
            }
            guard let authorizer = pluginFilterMutationAuthorizer,
                  let transaction = pluginAssociationTransaction else {
                return reject(envelope, code: .dispatchNotConfigured, operation: nil, peer: context.identity)
            }
            do {
                // Re-authorize at commit time. No prepare result or App-supplied replacement bytes
                // are trusted across the confirmation boundary.
                let prepared = try authorizer.prepare(request, now: now)
                // A durable audit acceptance is required before any write. A later completion-audit
                // failure must never turn an already-committed transaction into a rejection.
                do {
                    try audit.append(HelperAuditRecord(requestID: envelope.requestID, peer: context.identity,
                        outcome: .accepted, reasonCode: "plugin_association_commit_authorized"))
                } catch {
                    return reject(envelope, code: .pluginMutationAuditUnavailable, operation: nil, peer: context.identity)
                }
                let receipt: HelperPluginFilterMutationCommitReceipt
                if prepared.disposition == .alreadyInRequestedState {
                    receipt = HelperPluginFilterMutationCommitReceipt(requestID: request.requestID,
                        pluginID: request.pluginID, action: request.action,
                        targetBundleIdentifier: request.targetBundleIdentifier, transactionID: nil,
                        disposition: .alreadyInRequestedState,
                        plistSHA256: prepared.response.previousPlistSHA256 ?? "",
                        manifestSHA256: prepared.response.previousManifestSHA256 ?? "",
                        completedAt: now)
                } else {
                    let committed = try transaction.execute(prepared)
                    receipt = HelperPluginFilterMutationCommitReceipt(requestID: request.requestID,
                        pluginID: request.pluginID, action: request.action,
                        targetBundleIdentifier: request.targetBundleIdentifier, transactionID: committed.transactionID,
                        disposition: .committed, plistSHA256: committed.plistSHA256,
                        manifestSHA256: committed.manifestSHA256, completedAt: committed.completedAt)
                }
                let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
                let responseData = try encoder.encode(receipt)
                // Best-effort completion event only. The pre-commit authorization event is the
                // fail-closed audit barrier; do not report failure after a successful disk commit.
                try? audit.append(HelperAuditRecord(requestID: envelope.requestID, peer: context.identity,
                    outcome: .accepted, reasonCode: receipt.transactionID == nil
                        ? "plugin_association_already_current" : "plugin_association_committed"))
                return HelperIPCEnvelope(messageType: .pluginFilterMutationCommitted, requestID: envelope.requestID,
                    createdAt: now, nonce: context.sessionNonce, payload: responseData)
            } catch {
                return reject(envelope, code: .pluginMutationAuthorizationFailed, operation: nil, peer: context.identity)
            }

        case .pluginUninstallRequest:
            guard let payload = envelope.payload,
                  let request = Self.decodePluginUninstall(payload),
                  request.requestID == envelope.requestID,
                  abs(request.createdAt.timeIntervalSince(envelope.createdAt)) <= 5,
                  request.validate(now: now, clockSkewLimit: clockSkewLimit),
                  request.operatorConfirmed else {
                return reject(envelope, code: .malformedPluginUninstall, operation: nil, peer: context.identity)
            }
            guard recoveryStatus() == .clean else {
                return reject(envelope, code: .pluginUninstallRecoveryRequired, operation: nil, peer: context.identity)
            }
            guard let authorizer = pluginUninstallAuthorizer,
                  let transaction = pluginUninstallTransaction else {
                return reject(envelope, code: .dispatchNotConfigured, operation: nil, peer: context.identity)
            }
            do {
                _ = try HelperRecoveryAuthorization.authorize(context: context,
                    transactionID: request.requestID, requestNonce: request.requestID,
                    operatorConfirmed: request.operatorConfirmed, now: now,
                    clockSkewLimit: clockSkewLimit)
                _ = try authorizer.prepare(request, now: now)
                do {
                    try audit.append(HelperAuditRecord(requestID: envelope.requestID, peer: context.identity,
                        outcome: .accepted, reasonCode: "plugin_uninstall_authorized_read_only"))
                } catch {
                    return reject(envelope, code: .pluginUninstallAuditUnavailable, operation: nil, peer: context.identity)
                }
                guard Self.pluginUninstallExecutionReleased else {
                    let response = HelperPluginUninstallResponse(requestID: request.requestID,
                        pluginID: request.pluginID, status: .executionNotReleased,
                        reasonCode: "uninstall_authorized_execution_gate_closed", transactionID: nil, completedAt: now)
                    let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
                    return HelperIPCEnvelope(messageType: .pluginUninstallResponse, requestID: envelope.requestID,
                        createdAt: now, nonce: context.sessionNonce, payload: try? encoder.encode(response))
                }
                // Rebuild ownership, hashes and filter/association consistency immediately
                // before transaction entry; no UI-provided activation state is trusted.
                let fresh = try authorizer.prepare(request, now: now)
                let receipt = try transaction.execute(proof: fresh.ownershipProof,
                    transactionID: request.requestID,
                    preMutationAuthorization: {
                        let lastCheck = try authorizer.prepare(request, now: Date())
                        guard lastCheck.ownershipProof == fresh.ownershipProof else {
                            throw HelperPluginUninstallAuthorizer.AuthorizationError.associationStateMismatch
                        }
                    })
                let response = HelperPluginUninstallResponse(requestID: request.requestID,
                    pluginID: request.pluginID, status: .uninstalled, reasonCode: "three_file_uninstall_committed",
                    transactionID: receipt.transactionID, completedAt: now)
                try? audit.append(HelperAuditRecord(requestID: envelope.requestID, peer: context.identity,
                    outcome: .succeeded, reasonCode: "plugin_uninstall_committed",
                    changedRelativePaths: [request.dylibFileName, request.plistFileName,
                        String(request.dylibFileName.dropLast(6)) + ".fk.json"]))
                let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
                return HelperIPCEnvelope(messageType: .pluginUninstallResponse, requestID: envelope.requestID,
                    createdAt: now, nonce: context.sessionNonce, payload: try? encoder.encode(response))
            } catch {
                return reject(envelope, code: .pluginUninstallAuthorizationFailed, operation: nil, peer: context.identity)
            }

        case .deploymentBatchRequest:
            guard let payload = envelope.payload,
                  let batch = Self.decodeBatch(payload),
                  batch.batchID == envelope.requestID,
                  abs(batch.createdAt.timeIntervalSince(envelope.createdAt)) <= 5,
                  (try? batch.validate(now: now, clockSkewLimit: clockSkewLimit)) != nil else {
                return reject(envelope, code: .malformedBatch, operation: nil, peer: context.identity)
            }
            switch recoveryStatus() {
            case .clean: break
            case .legacyRecoveryRequired, .threeFileRecoveryRequired, .bothRecoveryRequired, .associationTransactionRecoveryRequired:
                return reject(envelope, code: .recoveryRequired, operation: nil, peer: context.identity)
            case .invalidJournal, .unavailable:
                return reject(envelope, code: .invalidTransactionJournal, operation: nil, peer: context.identity)
            }
            guard Self.executionReleased, manifest.executionEnabled else {
                return reject(envelope, code: .executionDisabled, operation: nil, peer: context.identity)
            }
            guard let deploymentPipeline else {
                return reject(envelope, code: .dispatchNotConfigured, operation: nil, peer: context.identity)
            }
            // Persist the immutable batch binding only after all read-only gates pass. A process
            // restart converts an in-flight record to indeterminate and blocks automatic replay.
            let transactionID = UUID()
            switch deploymentIdempotencyLedger.begin(batchID: batch.batchID, digest: batch.batchSHA256,
                requestIDs: batch.operations.map(\.requestID), transactionID: transactionID) {
            case .accepted: break
            case .existing(.inProgress):
                return reject(envelope, code: .deploymentBatchInProgress, operation: nil, peer: context.identity)
            case .existing(.indeterminate):
                return reject(envelope, code: .deploymentBatchOutcomeUnknown, operation: nil, peer: context.identity)
            case .existing(.completed):
                return reject(envelope, code: .replayedRequest, operation: nil, peer: context.identity)
            case .existing(.rolledBack):
                return reject(envelope, code: .deploymentBatchRolledBack, operation: nil, peer: context.identity)
            case .conflict:
                return reject(envelope, code: .deploymentBatchConflict, operation: nil, peer: context.identity)
            }
            do {
                let receipt = try deploymentPipeline.execute(batch, context: context, now: now, transactionID: transactionID)
                let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
                let payload = try encoder.encode(receipt)
                guard deploymentIdempotencyLedger.finish(batchID: batch.batchID, digest: batch.batchSHA256, state: .completed) else {
                    return reject(envelope, code: .deploymentBatchOutcomeUnknown, operation: nil, peer: context.identity)
                }
                // The durable completed record is authoritative. Completion audit is best-effort
                // and must not downgrade a committed batch if the audit sink is unavailable.
                try? audit.append(HelperAuditRecord(requestID: envelope.requestID, peer: context.identity,
                    outcome: .accepted, reasonCode: "deployment_batch_committed"))
                return HelperIPCEnvelope(messageType: .deploymentBatchReceipt, requestID: envelope.requestID,
                    createdAt: now, nonce: context.sessionNonce, payload: payload)
            } catch HelperDeploymentPipeline.PipelineError.authorizationFailed {
                _ = deploymentIdempotencyLedger.finish(batchID: batch.batchID, digest: batch.batchSHA256, state: .indeterminate)
                return reject(envelope, code: .authorizationFailed, operation: nil, peer: context.identity)
            } catch HelperDeploymentPipeline.PipelineError.invalidBatch,
                    HelperDeploymentPipeline.PipelineError.proofMismatch,
                    HelperDeploymentPipeline.PipelineError.planMismatch {
                _ = deploymentIdempotencyLedger.finish(batchID: batch.batchID, digest: batch.batchSHA256, state: .indeterminate)
                return reject(envelope, code: .malformedBatch, operation: nil, peer: context.identity)
            } catch {
                _ = deploymentIdempotencyLedger.finish(batchID: batch.batchID, digest: batch.batchSHA256, state: .indeterminate)
                return reject(envelope, code: .deploymentFailed, operation: nil, peer: context.identity)
            }

        case .operationRequest:
            guard let payload = envelope.payload,
                  let request = Self.decodeOperation(payload),
                  request.requestID == envelope.requestID,
                  abs(request.createdAt.timeIntervalSince(envelope.createdAt)) <= 5,
                  abs(now.timeIntervalSince(request.createdAt)) <= clockSkewLimit,
                  request.pluginID != UUID(uuidString: "00000000-0000-0000-0000-000000000000"),
                  Self.validOperationShape(request) else {
                return reject(envelope, code: .malformedOperation, operation: nil, peer: context.identity)
            }

            // The global release gate is intentionally false. Even a mistakenly enabled
            // on-disk manifest cannot activate deployment until a separately reviewed release.
            switch recoveryStatus() {
            case .clean: break
            case .legacyRecoveryRequired, .threeFileRecoveryRequired, .bothRecoveryRequired, .associationTransactionRecoveryRequired:
                return reject(envelope, code: .recoveryRequired, operation: request.operation, peer: context.identity)
            case .invalidJournal, .unavailable:
                return reject(envelope, code: .invalidTransactionJournal, operation: request.operation, peer: context.identity)
            }
            guard Self.executionReleased, manifest.executionEnabled else {
                return reject(envelope, code: .executionDisabled, operation: request.operation, peer: context.identity)
            }
            // P1-25 wires the dispatch boundary, not the privileged executor. This branch remains
            // fail-closed even if a test or edited manifest flips the configuration bit.
            return reject(envelope, code: .dispatchNotConfigured, operation: request.operation, peer: context.identity)

        default:
            return reject(envelope, code: .messageNotAllowed, operation: nil, peer: context.identity)
        }
    }

    private func reject(_ envelope: HelperIPCEnvelope, code: RejectionCode,
                        operation: HelperOperation?, peer: HelperPeerIdentity) -> HelperIPCEnvelope {
        let record = HelperAuditRecord(requestID: envelope.requestID, operation: operation, peer: peer,
            outcome: .rejected, reasonCode: code.rawValue)
        do { try audit.append(record) } catch {
            // Never turn an audit failure into permission to continue. The response still reports
            // the original denial; the missing audit event is detectable through service logs.
        }
        let payload = try? JSONEncoder().encode(Rejection(code: code, message: code.rawValue))
        return HelperIPCEnvelope(messageType: .rejected, requestID: envelope.requestID,
                                 payload: payload)
    }

    private func recoveryStatus() -> HelperRecoveryStatus {
        let detail: HelperStartupRecoveryCheck.Detail
        guard let pluginDirectory else { return .unavailable }
        detail = HelperStartupRecoveryCheck().inspectDetailed(pluginDirectory: pluginDirectory, deploymentLedgerStore: deploymentLedgerStore)
        switch detail {
        case .clean: return .clean
        case .legacyRecoveryRequired: return .legacyRecoveryRequired
        case .threeFileRecoveryRequired: return .threeFileRecoveryRequired
        case .bothRecoveryRequired: return .bothRecoveryRequired
        case .associationTransactionRecoveryRequired: return .associationTransactionRecoveryRequired
        case .pluginUninstallRecoveryRequired: return .threeFileRecoveryRequired
        case .invalidJournal: return .invalidJournal
        }
    }

    private static func decodeAppPluginActivationTransactionQuery(_ data: Data) -> HelperAppPluginActivationTransactionQuery? {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(HelperAppPluginActivationTransactionQuery.self, from: data)
    }

    private static func decodeAppPluginActivationTransactionReconciliationRequest(_ data: Data) -> HelperAppPluginActivationTransactionReconciliationRequest? {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(HelperAppPluginActivationTransactionReconciliationRequest.self, from: data)
    }

    private static func makeActivationTransactionStatus(
        query: HelperAppPluginActivationTransactionQuery,
        record: HelperAppPluginActivationTransactionRecord?, checkedAt: Date
    ) -> HelperAppPluginActivationTransactionStatus {
        let filterHash: String? = {
            guard let record else { return nil }
            switch record.state {
            case .committed: return record.filterAfterSHA256
            case .rolledBack: return record.filterBeforeSHA256
            case .executing, .outcomeUnknown: return nil
            }
        }()
        let manifestHash: String? = {
            guard let record else { return nil }
            switch record.state {
            case .committed: return record.manifestAfterSHA256
            case .rolledBack: return record.manifestBeforeSHA256
            case .executing, .outcomeUnknown: return nil
            }
        }()
        return HelperAppPluginActivationTransactionStatus(queryRequestID: query.requestID,
            commandRequestID: query.commandRequestID, pluginID: query.pluginID,
            targetBundleIdentifier: record?.targetBundleIdentifier ?? query.targetBundleIdentifier,
            state: record?.state, transactionID: record?.transactionID,
            filterSHA256: filterHash, manifestSHA256: manifestHash, checkedAt: checkedAt)
    }

    private static func decodeAppPluginActivationCommand(_ data: Data) -> HelperAppPluginActivationCommand? {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(HelperAppPluginActivationCommand.self, from: data)
    }

    private static func decodeAppPluginActivationCommit(_ data: Data) -> HelperAppPluginActivationCommitRequest? {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(HelperAppPluginActivationCommitRequest.self, from: data)
    }

    private static func decodePluginIdentityAttestation(_ data: Data) -> HelperPluginIdentityAttestationRequest? {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(HelperPluginIdentityAttestationRequest.self, from: data)
    }

    private static func decodePluginFilterMutation(_ data: Data) -> HelperPluginFilterMutationRequest? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(HelperPluginFilterMutationRequest.self, from: data)
    }

    private static func decodePluginUninstall(_ data: Data) -> HelperPluginUninstallRequest? {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(HelperPluginUninstallRequest.self, from: data)
    }

    private static func decodeMaintenanceRequest(_ data: Data) -> HelperMaintenanceRecoveryRequest? {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(HelperMaintenanceRecoveryRequest.self, from: data)
    }

    private static func decodeBatch(_ data: Data) -> HelperDeploymentBatchRequest? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(HelperDeploymentBatchRequest.self, from: data)
    }

    private static func decodeOperation(_ data: Data) -> HelperOperationRequest? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(HelperOperationRequest.self, from: data)
    }

    private static func validOperationShape(_ request: HelperOperationRequest) -> Bool {
        guard HelperPolicy.isSafeLeafName(request.targetFileName) else { return false }
        switch request.operation {
        case .installDylib:
            return request.targetFileName.lowercased().hasSuffix(".dylib") &&
                request.stagingRelativePath.map(HelperPolicy.isSafeRelativePath) == true &&
                request.expectedSHA256.map(HelperPolicy.isValidHash) == true
        case .replaceFilterPlist:
            return request.targetFileName.lowercased().hasSuffix(".plist") &&
                request.stagingRelativePath.map(HelperPolicy.isSafeRelativePath) == true &&
                request.expectedSHA256.map(HelperPolicy.isValidHash) == true
        case .removeUnmanagedDylib:
            // Removal stays unavailable until a distinct ownership-bound delete authorization exists.
            return false
        }
    }
}
