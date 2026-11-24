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
        case verifyArtifacts, preservePreviousRelease, stageRelease, activateRelease
        case verifyService, commit, beginRollback, completeRollback, requireManualIntervention
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
        self.schemaVersion = 1
        self.transactionID = transactionID
        self.action = action
        self.releaseIdentifier = releaseIdentifier
        self.generation = generation
        self.state = .prepared
        self.sequence = 0
        self.previousEventHash = String(repeating: "0", count: 64)
        self.entries = []
    }

    mutating func apply(_ event: Event) throws {
        let next: State
        switch (state, event) {
        case (.prepared, .verifyArtifacts): next = .artifactsVerified
        case (.artifactsVerified, .preservePreviousRelease) where action == .upgrade || action == .repin: next = .previousReleasePreserved
        case (.artifactsVerified, .stageRelease) where action == .install || action == .start: next = .staged
        case (.previousReleasePreserved, .stageRelease): next = .staged
        case (.staged, .activateRelease): next = .activated
        case (.activated, .verifyService): next = .serviceVerified
        case (.serviceVerified, .commit): next = .committed
        case (.prepared, .beginRollback), (.artifactsVerified, .beginRollback),
             (.previousReleasePreserved, .beginRollback), (.staged, .beginRollback),
             (.activated, .beginRollback): next = .rollbackRequired
        case (.rollbackRequired, .completeRollback): next = .rolledBack
        case (.rollbackRequired, .requireManualIntervention): next = .manualIntervention
        case (.prepared, .requireManualIntervention), (.artifactsVerified, .requireManualIntervention),
             (.previousReleasePreserved, .requireManualIntervention), (.staged, .requireManualIntervention),
             (.activated, .requireManualIntervention): next = .manualIntervention
        default: throw JournalError.invalidTransition
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
        guard schemaVersion == 1, generation > 0, !releaseIdentifier.isEmpty,
              sequence == UInt64(entries.count) else { throw JournalError.invalidHeader }
        var expectedPrevious = String(repeating: "0", count: 64)
        var expectedPriorState: State = .prepared
        for (offset, entry) in entries.enumerated() {
            let expectedSequence = UInt64(offset + 1)
            guard entry.sequence == expectedSequence,
                  entry.priorState == expectedPriorState,
                  entry.previousHash == expectedPrevious,
                  HelperPolicy.isValidHash(entry.hash) else { throw JournalError.corruptChain }
            let material = "\(transactionID.uuidString.lowercased())|\(entry.sequence)|\(entry.priorState.rawValue)|\(entry.event.rawValue)|\(entry.resultingState.rawValue)|\(entry.previousHash)"
            let expectedHash = SHA256Digest.hex(Data(material.utf8))
            guard entry.hash == expectedHash else { throw JournalError.corruptChain }
            expectedPrevious = expectedHash
            expectedPriorState = entry.resultingState
        }
        guard expectedPrevious == previousEventHash, expectedPriorState == state else {
            throw JournalError.corruptChain
        }
    }
}
