import Foundation

/// Combines the durable journal with descriptor-observed release inventories.
/// This coordinator is deliberately decision-only: it never starts/stops launchd or mutates files.
struct HelperInstallerRecoveryCoordinator {
    enum Inventory: Equatable { case absent, complete, previousRelease, partial, unexpected }
    enum Decision: Equatable {
        case evidenceConsistentButExecutionNotAuthorized(next: HelperInstallerTransactionJournal.PendingOperation?)
        case keepServiceStopped(reason: String)
    }
    struct Assessment: Equatable {
        let active: Inventory
        let staged: Inventory
        let previous: Inventory
        let decision: Decision
    }

    func assess(journal: HelperInstallerTransactionJournal,
                verifiedRelease: HelperRootReleaseSet.Verified,
                observation: HelperInstallerArtifactReconciliationBackend.Result,
                previousExpectedHashes: [HelperRootReleaseSet.Artifact: String]?) -> Assessment {
        let active = Self.classifyActive(observation.activeArtifacts, target: verifiedRelease.hashes,
                                        previous: previousExpectedHashes)
        let staged = Self.classify(observation.stagedArtifacts, expected: verifiedRelease.hashes)
        let previous: Inventory
        if let expected = previousExpectedHashes {
            previous = Self.classify(observation.previousArtifacts, expected: expected)
        } else {
            previous = Self.classifyUnspecified(observation.previousArtifacts)
        }

        func stopped(_ reason: String) -> Assessment {
            .init(active: active, staged: staged, previous: previous, decision: .keepServiceStopped(reason: reason))
        }
        do { try journal.validateChain() } catch { return stopped("journal chain is invalid") }
        guard Set(verifiedRelease.hashes.keys) == Set(HelperRootReleaseSet.Artifact.allCases),
              verifiedRelease.hashes.values.allSatisfy(HelperPolicy.isValidHash),
              verifiedRelease.generation == journal.generation,
              verifiedRelease.releaseIdentifier == journal.releaseIdentifier,
              observation.ownershipVerified else {
            return stopped("journal, signed release identity, or filesystem ownership does not agree")
        }
        if active == .partial || active == .unexpected || staged == .partial || staged == .unexpected
            || previous == .partial || previous == .unexpected {
            return stopped("active, staged, or previous release inventory is partial or has unexpected hashes")
        }
        if journal.action == .upgrade || journal.action == .repin,
           journal.state != .prepared, journal.pendingOperation != .verifyArtifacts {
            guard previousExpectedHashes != nil, previous == .complete else {
                return stopped("upgrade/repin previous release is absent, incomplete, or not hash-verified")
            }
        }
        if journal.state == .manualIntervention || journal.state == .rollbackRequired || journal.state == .rolledBack {
            return stopped("journal state requires rollback verification or manual intervention")
        }
        if journal.state == .committed {
            guard active == .complete, observation.activePointerMatchesObservedArtifacts,
                  observation.activeReleasePointer?.releaseIdentifier == verifiedRelease.releaseIdentifier,
                  observation.activeReleasePointer?.generation == verifiedRelease.generation else {
                return stopped("committed journal disagrees with active artifacts or active-release pointer")
            }
            return .init(active: active, staged: staged, previous: previous,
                         decision: .evidenceConsistentButExecutionNotAuthorized(next: nil))
        }
        if journal.state == .activated || journal.state == .serviceVerified {
            guard active == .complete, observation.activePointerMatchesObservedArtifacts,
                  observation.activeReleasePointer?.releaseIdentifier == verifiedRelease.releaseIdentifier,
                  observation.activeReleasePointer?.generation == verifiedRelease.generation else {
                return stopped("journal claims activation but active release pointer/artifacts do not prove it")
            }
        }
        if journal.state == .staged && staged != .complete {
            return stopped("journal claims staged release but staged artifacts do not match the verified release")
        }
        let beforeActivation = journal.state == .prepared || journal.state == .artifactsVerified
            || journal.state == .previousReleasePreserved || journal.state == .staged
        if beforeActivation {
            if journal.action == .upgrade || journal.action == .repin {
                guard active == .previousRelease else {
                    return stopped("before activation, active files must still match the verified previous release")
                }
            } else if active != .absent {
                return stopped("first-install journal unexpectedly has active release artifacts")
            }
        }
        if let pending = journal.pendingOperation {
            switch pending {
            case .stageRelease where staged != .complete && staged != .absent:
                return stopped("stage intent is inconsistent with a partial staged artifact set")
            case .activateRelease where staged != .complete && active != .complete:
                return stopped("activation intent has neither a complete staged nor active release")
            case .commitProvisioning where active != .complete:
                return stopped("commit intent exists without a complete active release")
            default: break
            }
        }
        // Even a consistent snapshot is not permission to execute. A separate reviewed executor
        // must reacquire the acceptance lock and re-observe every artifact before any side effect.
        let next = (try? HelperInstallerRecoveryAssessment.assess(journal).recommendation).flatMap { recommendation -> HelperInstallerTransactionJournal.PendingOperation? in
            switch recommendation {
            case .beginNextOperation(let operation), .reconcilePendingOperation(let operation): return operation
            default: return nil
            }
        }
        return .init(active: active, staged: staged, previous: previous,
                     decision: .evidenceConsistentButExecutionNotAuthorized(next: next))
    }

    private static func hashes(_ states: [HelperRootReleaseSet.Artifact: HelperInstallerDescriptorFilesystemObserver.ArtifactState]) -> [HelperRootReleaseSet.Artifact: String] {
        states.reduce(into: [:]) { output, item in
            if case .present(let record) = item.value { output[item.key] = record.sha256 }
        }
    }

    private static func classifyActive(_ states: [HelperRootReleaseSet.Artifact: HelperInstallerDescriptorFilesystemObserver.ArtifactState],
                                       target: [HelperRootReleaseSet.Artifact: String],
                                       previous: [HelperRootReleaseSet.Artifact: String]?) -> Inventory {
        let targetState = classify(states, expected: target)
        if targetState != .unexpected { return targetState }
        if let previous, classify(states, expected: previous) == .complete { return .previousRelease }
        return targetState
    }

    private static func classify(_ states: [HelperRootReleaseSet.Artifact: HelperInstallerDescriptorFilesystemObserver.ArtifactState],
                                 expected: [HelperRootReleaseSet.Artifact: String]) -> Inventory {
        guard Set(states.keys) == Set(HelperRootReleaseSet.Artifact.allCases),
              Set(expected.keys) == Set(HelperRootReleaseSet.Artifact.allCases) else { return .unexpected }
        let present = states.values.filter { if case .present = $0 { return true }; return false }.count
        if present == 0 { return .absent }
        if present != HelperRootReleaseSet.Artifact.allCases.count { return .partial }
        return hashes(states) == expected ? .complete : .unexpected
    }

    private static func classifyUnspecified(_ states: [HelperRootReleaseSet.Artifact: HelperInstallerDescriptorFilesystemObserver.ArtifactState]) -> Inventory {
        guard !states.isEmpty else { return .absent }
        let present = states.values.filter { if case .present = $0 { return true }; return false }.count
        if present == 0 { return .absent }
        if present != states.count { return .partial }
        return .complete
    }
}
