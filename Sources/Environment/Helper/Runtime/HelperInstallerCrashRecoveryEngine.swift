import Foundation

/// Facts collected by a privileged, descriptor-relative filesystem observer. This is deliberately
/// a value object: it performs no filesystem, launchd, Keychain, or service operations itself.
struct HelperInstallerRecoverySnapshot: Equatable {
    let stagedArtifactHashes: [HelperRootReleaseSet.Artifact: String]
    let artifactOwnershipVerified: Bool
    let previousReleasePreserved: Bool
    let previousArtifactHashes: [HelperRootReleaseSet.Artifact: String]?
    let previousArtifactOwnershipVerified: Bool
    let stagedReleaseIdentifier: String?
    let activeReleaseIdentifier: String?
    let serviceRunning: Bool
    let serviceIdentityMatchesRelease: Bool
    let provisioningEnvelopeSHA256: String?
    let previousProvisioningEnvelopeSHA256: String?
}

/// A conservative, side-effect-free decision. A future recovery backend must revalidate the
/// snapshot under the shared acceptance lock immediately before carrying out this action.
struct HelperInstallerCrashRecoveryEngine {
    enum Action: Equatable {
        case recordCompletion(HelperInstallerTransactionJournal.Event)
        case beginNextOperation(HelperInstallerTransactionJournal.PendingOperation)
        case retryIdempotentOperation(HelperInstallerTransactionJournal.PendingOperation)
        case rejectProvisioningAndRollback
        case stopServiceAndRequireManualIntervention
        case noAction
    }

    struct Assessment: Equatable {
        let action: Action
        let reason: String
    }

    func assess(journal: HelperInstallerTransactionJournal,
                release: HelperRootReleaseSet.Verified,
                targetProvisioningSHA256: String,
                previousReleaseHashes: [HelperRootReleaseSet.Artifact: String]? = nil,
                snapshot: HelperInstallerRecoverySnapshot) -> Assessment {
        do { try journal.validateChain() } catch {
            return .init(action: .stopServiceAndRequireManualIntervention,
                         reason: "journal chain is invalid")
        }
        guard HelperPolicy.isValidHash(targetProvisioningSHA256),
              Set(snapshot.stagedArtifactHashes.keys).isSubset(of: Set(HelperRootReleaseSet.Artifact.allCases)),
              Set(release.hashes.keys) == Set(HelperRootReleaseSet.Artifact.allCases),
              snapshot.stagedArtifactHashes.values.allSatisfy(HelperPolicy.isValidHash),
              release.hashes.values.allSatisfy(HelperPolicy.isValidHash),
              snapshot.artifactOwnershipVerified,
              journal.releaseIdentifier == release.releaseIdentifier,
              journal.generation == release.generation else {
            return .init(action: .stopServiceAndRequireManualIntervention,
                         reason: "release identity, artifact hashes, or ownership cannot be proven")
        }
        let targetArtifactsPresent = snapshot.stagedArtifactHashes == release.hashes
        let noTargetArtifactsPresent = snapshot.stagedArtifactHashes.isEmpty
        if !targetArtifactsPresent && !noTargetArtifactsPresent {
            return .init(action: .stopServiceAndRequireManualIntervention,
                         reason: "partial or unexpected staged artifact set")
        }
        if journal.action == .upgrade || journal.action == .repin,
           journal.state != .prepared, journal.pendingOperation != .verifyArtifacts {
            guard let expectedPrevious = previousReleaseHashes,
                  Set(expectedPrevious.keys) == Set(HelperRootReleaseSet.Artifact.allCases),
                  expectedPrevious.values.allSatisfy(HelperPolicy.isValidHash),
                  snapshot.previousArtifactOwnershipVerified,
                  snapshot.previousArtifactHashes == expectedPrevious else {
                return .init(action: .stopServiceAndRequireManualIntervention,
                             reason: "previous release hash or ownership evidence is incomplete")
            }
            if !snapshot.previousReleasePreserved {
                if journal.pendingOperation == .preservePreviousRelease {
                    return .init(action: .retryIdempotentOperation(.preservePreviousRelease),
                                 reason: "verified previous artifacts are available for idempotent preservation")
                }
                if journal.state != .artifactsVerified || journal.pendingOperation != nil {
                    return .init(action: .stopServiceAndRequireManualIntervention,
                                 reason: "previous release was not durably preserved before staging")
                }
            }
        }

        if journal.state == .manualIntervention {
            return .init(action: .stopServiceAndRequireManualIntervention,
                         reason: "journal already requires manual intervention")
        }
        if journal.state == .rolledBack {
            return .init(action: .stopServiceAndRequireManualIntervention,
                         reason: "previous release identity must be independently verified before service restart")
        }
        if journal.state == .committed {
            guard targetArtifactsPresent,
                  snapshot.activeReleaseIdentifier == release.releaseIdentifier,
                  snapshot.provisioningEnvelopeSHA256 == targetProvisioningSHA256,
                  snapshot.serviceIdentityMatchesRelease else {
                return .init(action: .stopServiceAndRequireManualIntervention,
                             reason: "committed journal disagrees with active release or provisioning")
            }
            return .init(action: .noAction, reason: "committed release and provisioning agree")
        }
        if journal.state == .staged || journal.state == .activated || journal.state == .serviceVerified {
            guard targetArtifactsPresent else {
                return .init(action: .stopServiceAndRequireManualIntervention,
                             reason: "journal claims activation progress but target artifacts are absent or changed")
            }
        }
        if journal.state == .activated || journal.state == .serviceVerified {
            guard snapshot.activeReleaseIdentifier == release.releaseIdentifier else {
                return .init(action: .stopServiceAndRequireManualIntervention,
                             reason: "journal activation state disagrees with active release pointer")
            }
        }
        if journal.state == .serviceVerified && journal.pendingOperation == nil {
            guard snapshot.provisioningEnvelopeSHA256 == snapshot.previousProvisioningEnvelopeSHA256,
                  snapshot.provisioningEnvelopeSHA256 != targetProvisioningSHA256 else {
                return .init(action: .stopServiceAndRequireManualIntervention,
                             reason: "Provisioning changed without a durable commit intent")
            }
        }

        guard let pending = journal.pendingOperation else {
            let next: HelperInstallerTransactionJournal.PendingOperation
            switch journal.state {
            case .prepared: next = .verifyArtifacts
            case .artifactsVerified:
                next = (journal.action == .upgrade || journal.action == .repin) ? .preservePreviousRelease : .stageRelease
            case .previousReleasePreserved: next = .stageRelease
            case .staged: next = .activateRelease
            case .activated: next = .verifyService
            case .serviceVerified: next = .commitProvisioning
            case .rollbackRequired, .manualIntervention, .committed, .rolledBack:
                return .init(action: .stopServiceAndRequireManualIntervention,
                             reason: "transaction state requires filesystem-specific recovery")
            }
            return .init(action: .beginNextOperation(next),
                         reason: "last completion is durable; persist the next intent before executing it")
        }

        switch pending {
        case .verifyArtifacts:
            if targetArtifactsPresent {
                return .init(action: .recordCompletion(.verifyArtifacts),
                             reason: "all release artifact hashes and ownership match the signed release")
            }
            if noTargetArtifactsPresent {
                return .init(action: .retryIdempotentOperation(.verifyArtifacts),
                             reason: "artifact verification has no side effect and may be retried")
            }
            return .init(action: .stopServiceAndRequireManualIntervention,
                         reason: "partial or unexpected release artifact set")
        case .preservePreviousRelease:
            if snapshot.previousReleasePreserved {
                return .init(action: .recordCompletion(.preservePreviousRelease),
                             reason: "previous release backup is confirmed")
            }
            return .init(action: .retryIdempotentOperation(.preservePreviousRelease),
                         reason: "previous release preservation is not observed; backend must retry idempotently")
        case .stageRelease:
            if targetArtifactsPresent && snapshot.stagedReleaseIdentifier == release.releaseIdentifier {
                return .init(action: .recordCompletion(.stageRelease),
                             reason: "target release staging is confirmed")
            }
            if noTargetArtifactsPresent {
                return .init(action: .retryIdempotentOperation(.stageRelease),
                             reason: "target release staging is absent; backend must retry idempotently")
            }
            return .init(action: .stopServiceAndRequireManualIntervention,
                         reason: "staged release identifier or artifact hashes disagree")
        case .activateRelease:
            guard targetArtifactsPresent else {
                return .init(action: .stopServiceAndRequireManualIntervention,
                             reason: "target release artifacts are not fully staged")
            }
            if snapshot.activeReleaseIdentifier == release.releaseIdentifier {
                return .init(action: .recordCompletion(.activateRelease),
                             reason: "active release pointer and artifact set match target")
            }
            if snapshot.previousReleasePreserved,
               snapshot.stagedReleaseIdentifier == release.releaseIdentifier {
                return .init(action: .retryIdempotentOperation(.activateRelease),
                             reason: "old release is preserved and target is staged")
            }
            return .init(action: .stopServiceAndRequireManualIntervention,
                         reason: "activation state cannot be reconciled safely")
        case .verifyService:
            guard targetArtifactsPresent,
                  snapshot.activeReleaseIdentifier == release.releaseIdentifier,
                  snapshot.serviceRunning, snapshot.serviceIdentityMatchesRelease else {
                return .init(action: .stopServiceAndRequireManualIntervention,
                             reason: "service is not running with the verified target identity")
            }
            return .init(action: .recordCompletion(.verifyService),
                         reason: "running service identity matches the active verified release")
        case .commitProvisioning:
            guard targetArtifactsPresent,
                  snapshot.activeReleaseIdentifier == release.releaseIdentifier,
                  snapshot.serviceIdentityMatchesRelease else {
                return .init(action: .stopServiceAndRequireManualIntervention,
                             reason: "active release identity is not proven before provisioning reconciliation")
            }
            if snapshot.provisioningEnvelopeSHA256 == targetProvisioningSHA256 {
                return .init(action: .recordCompletion(.commit),
                             reason: "target provisioning envelope is already authoritative")
            }
            if let previous = snapshot.previousProvisioningEnvelopeSHA256,
               snapshot.provisioningEnvelopeSHA256 == previous {
                return .init(action: .rejectProvisioningAndRollback,
                             reason: "previous provisioning remains authoritative")
            }
            return .init(action: .stopServiceAndRequireManualIntervention,
                         reason: "provisioning authority is neither the target nor the known previous envelope")
        }
    }
}
