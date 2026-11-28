import Foundation

/// A deterministic journal reducer for a future trusted Root Installer. The reducer is pure:
/// persistence, fsync, filesystem operations and launchd calls are intentionally not provided.
struct HelperInstallerTransactionJournal: Codable, Equatable {
    enum State: String, Codable {
        case prepared, artifactsVerified, previousReleasePreserved, staged
        case activated, serviceVerified, committed
        case rollbackRequired, rolledBack, manualIntervention
    }

    enum Event: String, Codable {
        case intentVerifyArtifacts, intentPreservePreviousRelease, intentStageRelease
        case intentActivateRelease, intentVerifyService, intentCommitProvisioning
        case verifyArtifacts, preservePreviousRelease, stageRelease, activateRelease
        case verifyService, commit, rejectCommitProvisioning, beginRollback, completeRollback, requireManualIntervention
    }

    enum PendingOperation: String, Codable {
        case verifyArtifacts, preservePreviousRelease, stageRelease
        case activateRelease, verifyService, commitProvisioning
    }

    let schemaVersion: Int
    let transactionID: UUID
    let action: HelperInstallerTransactionPlan.Action
    let releaseIdentifier: String
    let generation: UInt64
    private(set) var state: State
    private(set) var sequence: UInt64
    private(set) var previousEventHash: String
    private(set) var entries: [Entry]
    /// Non-nil means the intent was durably recorded but its completion was not.
    /// Recovery must inspect the filesystem before retrying or advancing this operation.
    private(set) var pendingOperation: PendingOperation?

    struct Entry: Codable, Equatable {
        let sequence: UInt64
        let priorState: State
        let event: Event
        let resultingState: State
        let previousHash: String
        let hash: String
    }

    enum JournalError: Error, Equatable { case invalidHeader, invalidTransition, corruptChain }

    init(transactionID: UUID = UUID(), action: HelperInstallerTransactionPlan.Action,
         releaseIdentifier: String, generation: UInt64) throws {
        guard !releaseIdentifier.isEmpty, releaseIdentifier.count <= 128, generation > 0,
              action == .install || action == .upgrade || action == .repin else {
            throw JournalError.invalidHeader
        }
        self.schemaVersion = 2
        self.transactionID = transactionID
        self.action = action
        self.releaseIdentifier = releaseIdentifier
        self.generation = generation
        self.state = .prepared
        self.sequence = 0
        self.previousEventHash = String(repeating: "0", count: 64)
        self.entries = []
        self.pendingOperation = nil
    }

    mutating func apply(_ event: Event) throws {
        let next: State
        switch event {
        case .intentVerifyArtifacts:
            guard pendingOperation == nil, state == .prepared else { throw JournalError.invalidTransition }
            pendingOperation = .verifyArtifacts; next = state
        case .intentPreservePreviousRelease:
            guard pendingOperation == nil, state == .artifactsVerified,
                  action == .upgrade || action == .repin else { throw JournalError.invalidTransition }
            pendingOperation = .preservePreviousRelease; next = state
        case .intentStageRelease:
            guard pendingOperation == nil,
                  (state == .artifactsVerified && action == .install) || state == .previousReleasePreserved else { throw JournalError.invalidTransition }
            pendingOperation = .stageRelease; next = state
        case .intentActivateRelease:
            guard pendingOperation == nil, state == .staged else { throw JournalError.invalidTransition }
            pendingOperation = .activateRelease; next = state
        case .intentVerifyService:
            guard pendingOperation == nil, state == .activated else { throw JournalError.invalidTransition }
            pendingOperation = .verifyService; next = state
        case .intentCommitProvisioning:
            guard pendingOperation == nil, state == .serviceVerified else { throw JournalError.invalidTransition }
            pendingOperation = .commitProvisioning; next = state
        case .verifyArtifacts:
            guard pendingOperation == .verifyArtifacts else { throw JournalError.invalidTransition }
            pendingOperation = nil
            next = .artifactsVerified
        case .preservePreviousRelease:
            guard pendingOperation == .preservePreviousRelease else { throw JournalError.invalidTransition }
            pendingOperation = nil
            next = .previousReleasePreserved
        case .stageRelease:
            guard pendingOperation == .stageRelease else { throw JournalError.invalidTransition }
            pendingOperation = nil
            next = .staged
        case .activateRelease:
            guard pendingOperation == .activateRelease else { throw JournalError.invalidTransition }
            pendingOperation = nil
            next = .activated
        case .verifyService:
            guard pendingOperation == .verifyService else { throw JournalError.invalidTransition }
            pendingOperation = nil
            next = .serviceVerified
        case .commit:
            guard pendingOperation == .commitProvisioning else { throw JournalError.invalidTransition }
            pendingOperation = nil
            next = .committed
        case .rejectCommitProvisioning:
            guard pendingOperation == .commitProvisioning else { throw JournalError.invalidTransition }
            pendingOperation = nil
            next = state
        default:
            guard pendingOperation == nil || event == .requireManualIntervention else { throw JournalError.invalidTransition }
            switch (state, event) {
            case (.prepared, .beginRollback), (.artifactsVerified, .beginRollback),
                 (.previousReleasePreserved, .beginRollback), (.staged, .beginRollback),
                 (.activated, .beginRollback), (.serviceVerified, .beginRollback): next = .rollbackRequired
            case (.rollbackRequired, .completeRollback): next = .rolledBack
            case (.prepared, .requireManualIntervention), (.artifactsVerified, .requireManualIntervention),
                 (.previousReleasePreserved, .requireManualIntervention), (.staged, .requireManualIntervention),
                 (.activated, .requireManualIntervention), (.serviceVerified, .requireManualIntervention),
                 (.rollbackRequired, .requireManualIntervention): next = .manualIntervention
            default: throw JournalError.invalidTransition
            }
        }
        let nextSequence = sequence + 1
        let prior = state
        let previous = previousEventHash
        let material = "\(transactionID.uuidString.lowercased())|\(nextSequence)|\(prior.rawValue)|\(event.rawValue)|\(next.rawValue)|\(previous)"
        let digest = SHA256Digest.hex(Data(material.utf8))
        entries.append(Entry(sequence: nextSequence, priorState: prior, event: event,
                             resultingState: next, previousHash: previous, hash: digest))
        sequence = nextSequence
        state = next
        previousEventHash = digest
    }

    func validateChain() throws {
        guard schemaVersion == 2, generation > 0, !releaseIdentifier.isEmpty,
              sequence == UInt64(entries.count) else { throw JournalError.invalidHeader }
        var expectedPrevious = String(repeating: "0", count: 64)
        var expectedPriorState: State = .prepared
        var expectedPending: PendingOperation?
        for (offset, entry) in entries.enumerated() {
            let expectedSequence = UInt64(offset + 1)
            guard entry.sequence == expectedSequence,
                  entry.priorState == expectedPriorState,
                  entry.previousHash == expectedPrevious,
                  HelperPolicy.isValidHash(entry.hash) else { throw JournalError.corruptChain }
            let material = "\(transactionID.uuidString.lowercased())|\(entry.sequence)|\(entry.priorState.rawValue)|\(entry.event.rawValue)|\(entry.resultingState.rawValue)|\(entry.previousHash)"
            let expectedHash = SHA256Digest.hex(Data(material.utf8))
            guard entry.hash == expectedHash else { throw JournalError.corruptChain }
            let resulting = try Self.replay(entry.event, state: expectedPriorState,
                                            pending: &expectedPending, action: action)
            guard resulting == entry.resultingState else { throw JournalError.corruptChain }
            expectedPrevious = expectedHash
            expectedPriorState = resulting
        }
        guard expectedPrevious == previousEventHash, expectedPriorState == state,
              expectedPending == pendingOperation else { throw JournalError.corruptChain }
    }

    private static func replay(_ event: Event, state: State,
                               pending: inout PendingOperation?,
                               action: HelperInstallerTransactionPlan.Action) throws -> State {
        switch event {
        case .intentVerifyArtifacts:
            guard pending == nil, state == .prepared else { throw JournalError.corruptChain }
            pending = .verifyArtifacts; return state
        case .intentPreservePreviousRelease:
            guard pending == nil, state == .artifactsVerified,
                  action == .upgrade || action == .repin else { throw JournalError.corruptChain }
            pending = .preservePreviousRelease; return state
        case .intentStageRelease:
            guard pending == nil,
                  (state == .artifactsVerified && action == .install) || state == .previousReleasePreserved else { throw JournalError.corruptChain }
            pending = .stageRelease; return state
        case .intentActivateRelease:
            guard pending == nil, state == .staged else { throw JournalError.corruptChain }
            pending = .activateRelease; return state
        case .intentVerifyService:
            guard pending == nil, state == .activated else { throw JournalError.corruptChain }
            pending = .verifyService; return state
        case .intentCommitProvisioning:
            guard pending == nil, state == .serviceVerified else { throw JournalError.corruptChain }
            pending = .commitProvisioning; return state
        case .verifyArtifacts:
            guard pending == .verifyArtifacts else { throw JournalError.corruptChain }
            pending = nil; return .artifactsVerified
        case .preservePreviousRelease:
            guard pending == .preservePreviousRelease else { throw JournalError.corruptChain }
            pending = nil; return .previousReleasePreserved
        case .stageRelease:
            guard pending == .stageRelease else { throw JournalError.corruptChain }
            pending = nil; return .staged
        case .activateRelease:
            guard pending == .activateRelease else { throw JournalError.corruptChain }
            pending = nil; return .activated
        case .verifyService:
            guard pending == .verifyService else { throw JournalError.corruptChain }
            pending = nil; return .serviceVerified
        case .commit:
            guard pending == .commitProvisioning else { throw JournalError.corruptChain }
            pending = nil; return .committed
        case .rejectCommitProvisioning:
            guard pending == .commitProvisioning else { throw JournalError.corruptChain }
            pending = nil; return state
        case .beginRollback:
            guard pending == nil else { throw JournalError.corruptChain }
            switch state {
            case .prepared, .artifactsVerified, .previousReleasePreserved, .staged, .activated, .serviceVerified: return .rollbackRequired
            default: throw JournalError.corruptChain
            }
        case .completeRollback:
            guard pending == nil, state == .rollbackRequired else { throw JournalError.corruptChain }
            return .rolledBack
        case .requireManualIntervention:
            switch state {
            case .prepared, .artifactsVerified, .previousReleasePreserved, .staged, .activated, .serviceVerified, .rollbackRequired:
                return .manualIntervention
            default: throw JournalError.corruptChain
            }
        }
    }

}
