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

    private var serviceFactory: () throws -> HelperAppPluginActivationService = {
        try HelperAppPluginActivationService.production()
    }

    func installServiceFactoryForTesting(_ factory: @escaping () throws -> HelperAppPluginActivationService) {
        serviceFactory = factory
    }

    func prepare(plugin: PluginScanItem, activation: AppPluginActivationState,
                 desiredEnabled: Bool, snapshotRevision: UInt64) async {
        guard phase != .preparing && phase != .committing else { return }
        pending = nil
        lastProof = nil
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
                phase = .outcomeUnknown
                errorDescription = "commit_proof_invalid"
                PluginScanRegistry.shared.refresh()
                return
            }
            lastProof = proof
            self.pending = nil
            phase = .committed
            // The scan, not the proof alone, is the UI's next authoritative state source.
            PluginScanRegistry.shared.refresh()
        } catch HelperDeploymentCoordinator.CoordinatorError.executionNotReleased {
            phase = .blocked
            errorDescription = "activation_commit_release_closed"
        } catch {
            // A transport failure after Commit submission has an unknown outcome. Never retry
            // the same command automatically; invalidate the plan and obtain a fresh scan.
            self.pending = nil
            phase = .outcomeUnknown
            errorDescription = String(describing: error)
            PluginScanRegistry.shared.refresh()
        }
    }

    func invalidatePending(reason: String = "scan_snapshot_changed") {
        guard pending != nil else { return }
        pending = nil
        phase = .failed
        errorDescription = reason
    }
}
