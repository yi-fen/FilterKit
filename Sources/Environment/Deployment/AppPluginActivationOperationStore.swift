import Foundation
import SwiftUI

/// APP-detail orchestration state. A prepared plan is scoped to the exact scan revision;
/// a changed snapshot invalidates it. No optimistic enabled-state is written to the UI.
@MainActor
final class AppPluginActivationOperationStore: ObservableObject {
    enum Phase: Equatable {
        case idle
        case preparing
        case prepared
        case committing
        case committed
        case reconciling
        case reconciledCommitted
        case reconciledRolledBack
        case blocked
        case outcomeUnknown
        case failed
    }

    struct PendingOperation {
        let command: HelperAppPluginActivationCommand
        let plan: HelperAppPluginActivationPlan
        let snapshotRevision: UInt64
    }

    static let shared = AppPluginActivationOperationStore()

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var pending: PendingOperation?
    @Published private(set) var lastProof: HelperAppPluginActivationProof?
    @Published private(set) var errorDescription: String?
    @Published private(set) var outcomeResolution: AppPluginActivationOutcomeResolution?
    @Published private(set) var helperTransactionStatus: HelperAppPluginActivationTransactionStatus?

    private var uncertainCommand: HelperAppPluginActivationCommand?
    private let recoveryHintKey = "filterkit.appActivation.pendingUnknown.v1"

    private init() {
        if let data = UserDefaults.standard.data(forKey: recoveryHintKey),
           let command = try? JSONDecoder().decode(HelperAppPluginActivationCommand.self, from: data),
           command.validatesForRecoveryHint() {
            uncertainCommand = command
            phase = .outcomeUnknown
            outcomeResolution = .stillIndeterminate
            errorDescription = "restored_pending_helper_verification"
        } else {
            UserDefaults.standard.removeObject(forKey: recoveryHintKey)
            _ = UserDefaults.standard.synchronize()
        }
    }

    private func persistRecoveryHint(_ command: HelperAppPluginActivationCommand?) {
        guard let command, command.validatesForRecoveryHint(),
              let data = try? JSONEncoder().encode(command) else {
            UserDefaults.standard.removeObject(forKey: recoveryHintKey)
            _ = UserDefaults.standard.synchronize()
            return
        }
        UserDefaults.standard.set(data, forKey: recoveryHintKey)
        _ = UserDefaults.standard.synchronize()
    }

    private var serviceFactory: () throws -> HelperAppPluginActivationService = {
        try HelperAppPluginActivationService.production()
    }

    func installServiceFactoryForTesting(_ factory: @escaping () throws -> HelperAppPluginActivationService) {
        serviceFactory = factory
    }

    func prepare(plugin: PluginScanItem, activation: AppPluginActivationState,
                 desiredEnabled: Bool, snapshotRevision: UInt64) async {
        guard phase != .preparing && phase != .committing && phase != .outcomeUnknown else { return }
        pending = nil
        lastProof = nil
        outcomeResolution = nil
        helperTransactionStatus = nil
        uncertainCommand = nil
        errorDescription = nil
        phase = .preparing
        do {
            let service = try serviceFactory()
            let (command, plan) = try await service.prepare(plugin: plugin, activation: activation,
                desiredEnabled: desiredEnabled, snapshotRevision: snapshotRevision)
            guard PluginScanRegistry.shared.snapshotRevision == snapshotRevision else {
                phase = .failed
                errorDescription = "scan_snapshot_changed"
                return
            }
            pending = PendingOperation(command: command, plan: plan, snapshotRevision: snapshotRevision)
            phase = .prepared
        } catch {
            phase = .failed
            errorDescription = String(describing: error)
        }
    }

    func commit(userConfirmed: Bool, currentSnapshotRevision: UInt64) async {
        guard userConfirmed, let pending else { phase = .blocked; return }
        guard pending.snapshotRevision == currentSnapshotRevision,
              PluginScanRegistry.shared.snapshotRevision == currentSnapshotRevision else {
            self.pending = nil
            phase = .failed
            errorDescription = "scan_snapshot_changed"
            RuntimeEventLogger.recordPluginOperation("activation", outcome: .blocked,
                pluginID: pending.command.pluginID.uuidString,
                detail: "Activation was blocked because the plugin inventory changed.",
                traceID: pending.command.requestID.uuidString)
            PluginScanRegistry.shared.refresh()
            return
        }
        phase = .committing
        do {
            let service = try serviceFactory()
            let proof = try await service.commit(command: pending.command, plan: pending.plan,
                userConfirmed: true)
            guard proof.validates(command: pending.command) else {
                self.pending = nil
                uncertainCommand = pending.command
                persistRecoveryHint(pending.command)
                outcomeResolution = .stillIndeterminate
                phase = .outcomeUnknown
                errorDescription = "commit_proof_invalid"
                RuntimeEventLogger.recordPluginOperation("activation", outcome: .unknown,
                    pluginID: pending.command.pluginID.uuidString, traceID: pending.command.requestID.uuidString)
                PluginScanRegistry.shared.refresh()
                return
            }
            lastProof = proof
            RuntimeEventLogger.recordPluginOperation("activation", outcome: .completed,
                pluginID: pending.command.pluginID.uuidString, traceID: pending.command.requestID.uuidString)
            self.pending = nil
            phase = .committed
            // The scan, not the proof alone, is the UI's next authoritative state source.
            PluginScanRegistry.shared.refresh()
        } catch HelperDeploymentCoordinator.CoordinatorError.executionNotReleased {
            phase = .blocked
            errorDescription = "activation_commit_release_closed"
            RuntimeEventLogger.recordPluginOperation("activation", outcome: .blocked,
                pluginID: pending.command.pluginID.uuidString, traceID: pending.command.requestID.uuidString)
        } catch {
            // A transport failure after Commit submission has an unknown outcome. Never retry
            // the same command automatically; invalidate the plan and obtain a fresh scan.
            self.pending = nil
            uncertainCommand = pending.command
            persistRecoveryHint(pending.command)
            outcomeResolution = .stillIndeterminate
            phase = .outcomeUnknown
            errorDescription = String(describing: error)
            RuntimeEventLogger.recordPluginOperation("activation", outcome: .unknown,
                pluginID: pending.command.pluginID.uuidString, traceID: pending.command.requestID.uuidString)
            PluginScanRegistry.shared.refresh()
        }
    }

    /// Call only after a new authoritative PluginScanRegistry snapshot has been published.
    /// This never retries Commit and never manufactures a Helper proof.
    func reconcileUnknownOutcome(using observed: AppPluginActivationState?) {
        guard phase == .outcomeUnknown, let command = uncertainCommand,
              let observed,
              UUID(uuidString: observed.pluginID) == command.pluginID,
              HelperBundleIdentifierKey.make(observed.targetBundleIdentifier)
                == HelperBundleIdentifierKey.make(command.targetBundleIdentifier) else { return }
        let resolution = AppPluginActivationOutcomeReconciler().resolve(command: command, observed: observed)
        outcomeResolution = resolution
        switch resolution {
        case .desiredStateObserved:
            errorDescription = "desired_state_observed_without_commit_proof"
        case .previousStateObserved:
            errorDescription = "previous_state_observed_commit_not_confirmed"
        case .stillIndeterminate:
            errorDescription = "commit_outcome_still_indeterminate"
        }
        // Keep phase == .outcomeUnknown in all cases. A configuration snapshot is not
        // transaction evidence, and the user must not be shown a proven Commit receipt.
    }

    /// User-triggered Helper-side evidence reconciliation. This never resends Commit.
    func reconcileWithHelper(userConfirmed: Bool) async {
        guard userConfirmed, phase == .outcomeUnknown, let command = uncertainCommand else { return }
        phase = .reconciling
        do {
            let service = try serviceFactory()
            let status = try await service.reconcile(command: command, userConfirmed: true)
            helperTransactionStatus = status
            switch status.state {
            case .committed:
                phase = .reconciledCommitted
                errorDescription = "helper_transaction_committed"
                RuntimeEventLogger.recordPluginOperation("activation", outcome: .completed,
                    pluginID: command.pluginID.uuidString,
                    detail: "Helper confirmed the activation transaction committed.",
                    traceID: command.requestID.uuidString)
            case .rolledBack:
                phase = .reconciledRolledBack
                errorDescription = "helper_transaction_rolled_back"
                RuntimeEventLogger.recordPluginOperation("activation", outcome: .failed,
                    pluginID: command.pluginID.uuidString,
                    detail: "Helper confirmed the activation transaction rolled back.",
                    traceID: command.requestID.uuidString)
            case .executing, .outcomeUnknown, .none:
                phase = .outcomeUnknown
                errorDescription = "helper_transaction_still_unknown"
                RuntimeEventLogger.recordPluginOperation("activation", outcome: .unknown,
                    pluginID: command.pluginID.uuidString, traceID: command.requestID.uuidString)
            }
            PluginScanRegistry.shared.refresh()
        } catch {
            phase = .outcomeUnknown
            errorDescription = String(describing: error)
            RuntimeEventLogger.recordPluginOperation("activation", outcome: .unknown,
                pluginID: command.pluginID.uuidString, traceID: command.requestID.uuidString)
        }
    }

    func outcomeBelongs(pluginID: UUID?, targetBundleIdentifier: String) -> Bool {
        guard [.outcomeUnknown, .reconciling, .reconciledCommitted, .reconciledRolledBack].contains(phase),
              let command = uncertainCommand else { return false }
        return command.pluginID == pluginID &&
            HelperBundleIdentifierKey.make(command.targetBundleIdentifier)
                == HelperBundleIdentifierKey.make(targetBundleIdentifier)
    }

    /// Dismisses a scan-only observation without clearing the unresolved Helper command.
    func dismissScanObservation() {
        guard phase == .outcomeUnknown else { return }
        outcomeResolution = .stillIndeterminate
        errorDescription = "commit_outcome_still_indeterminate"
    }

    func clearReconciledOutcome() {
        // A scan snapshot is not durable Helper transaction proof. Only a terminal
        // Helper response may clear the persisted command recovery hint.
        let helperResolved = phase == .reconciledCommitted || phase == .reconciledRolledBack
        guard helperResolved else { return }
        uncertainCommand = nil
        persistRecoveryHint(nil)
        outcomeResolution = nil
        helperTransactionStatus = nil
        phase = .idle
        errorDescription = nil
    }

    func invalidatePending(reason: String = "scan_snapshot_changed") {
        guard pending != nil else { return }
        pending = nil
        phase = .failed
        errorDescription = reason
    }
}
