import Foundation

/// Pure in-memory recovery rehearsal. It models the intended transaction ordering without
/// opening files, writing a Journal, changing launchd state, or invoking a privileged executor.
enum HelperInstallerRecoveryDryRun {
    enum Step: String, CaseIterable {
        case journalIntent
        case stageArtifacts
        case preservePrevious
        case replaceActive
        case updatePointer
        case journalCommit
        case verifyRecoveredState
    }

    enum Disposition: Equatable {
        case inspectOnly
        case reconcileBeforeRetry
        case blocked(reason: String)
    }

    struct Snapshot: Equatable {
        var journalIntentWritten = false
        var journalCommitted = false
        var stagedHashes: [String]? = nil
        var previousHashes: [String]? = nil
        var activeHashes: [String]? = nil
        var pointerHashes: [String]? = nil
        var serviceStopped = true
        var ownershipVerified = true
        var journalChainValid = true
    }

    struct Result: Equatable {
        let completedSteps: [Step]
        let crashedAfter: Step?
        let snapshot: Snapshot
        let disposition: Disposition
        let evidenceDigest: String
        let repeatedAssessment: Disposition
        let invariants: [String: Bool]

        var passed: Bool {
            disposition == repeatedAssessment && invariants.values.allSatisfy { $0 }
        }
    }

    static func run(target: [String], previous: [String], crashAfter: Step? = nil,
                    corruptPointer: Bool = false, corruptJournal: Bool = false,
                    serviceRunning: Bool = false) -> Result {
        precondition(target.count == 3 && previous.count == 3)
        var state = Snapshot(serviceStopped: !serviceRunning, journalChainValid: !corruptJournal)
        var completed: [Step] = []
        let steps = Step.allCases
        for step in steps {
            switch step {
            case .journalIntent:
                state.journalIntentWritten = true
            case .stageArtifacts:
                state.stagedHashes = target
            case .preservePrevious:
                state.previousHashes = previous
            case .replaceActive:
                state.activeHashes = target
            case .updatePointer:
                state.pointerHashes = corruptPointer ? [target[0], target[1], "mismatch"] : target
            case .journalCommit:
                state.journalCommitted = true
            case .verifyRecoveredState:
                break
            }
            completed.append(step)
            if crashAfter == step { break }
        }
        let disposition = assess(state, target: target, previous: previous)
        let digest = stableDigest(state)
        let repeated = assess(state, target: target, previous: previous)
        let invariants: [String: Bool] = [
            "service-remains-stopped": state.serviceStopped,
            "journal-intent-precedes-side-effects": !hasSideEffects(state) || state.journalIntentWritten,
            "journal-chain-valid": state.journalChainValid,
            "ownership-verified": state.ownershipVerified,
            "committed-requires-active-target": !state.journalCommitted || state.activeHashes == target,
            "committed-requires-pointer-match": !state.journalCommitted || state.pointerHashes == target,
            "no-partial-active-set": state.activeHashes == nil || state.activeHashes?.count == 3
        ]
        return Result(completedSteps: completed, crashedAfter: crashAfter, snapshot: state,
                      disposition: disposition, evidenceDigest: digest,
                      repeatedAssessment: repeated, invariants: invariants)
    }

    static func assess(_ state: Snapshot, target: [String], previous: [String]) -> Disposition {
        guard state.serviceStopped else { return .blocked(reason: "service is running or state is unknown") }
        guard state.ownershipVerified, state.journalChainValid else { return .blocked(reason: "ownership or Journal chain is untrusted") }
        guard state.journalIntentWritten || !hasSideEffects(state) else { return .blocked(reason: "side effects exist without durable intent") }
        if let active = state.activeHashes, active.count != 3 { return .blocked(reason: "active inventory is partial") }
        if let active = state.activeHashes, active != target && active != previous {
            return .blocked(reason: "active inventory matches neither target nor previous release")
        }
        if state.journalCommitted {
            guard state.activeHashes == target, state.pointerHashes == target else {
                return .blocked(reason: "committed Journal disagrees with Active or Pointer")
            }
            return .inspectOnly
        }
        if state.pointerHashes != nil && state.pointerHashes != target && state.pointerHashes != previous {
            return .blocked(reason: "release pointer hash mismatch")
        }
        if state.activeHashes == target && state.pointerHashes == target { return .reconcileBeforeRetry }
        if state.stagedHashes != nil && state.stagedHashes != target { return .blocked(reason: "staged inventory mismatch") }
        if state.previousHashes != nil && state.previousHashes != previous { return .blocked(reason: "previous backup mismatch") }
        return state.journalIntentWritten ? .reconcileBeforeRetry : .inspectOnly
    }

    private static func hasSideEffects(_ state: Snapshot) -> Bool {
        state.stagedHashes != nil || state.previousHashes != nil || state.activeHashes != nil || state.pointerHashes != nil
    }

    private static func stableDigest(_ state: Snapshot) -> String {
        // Stable, dependency-free digest for deterministic host rehearsal identifiers only.
        // This is not a cryptographic attestation and must never be used as an authorization token.
        let flags = [state.journalIntentWritten, state.journalCommitted, state.serviceStopped,
                     state.ownershipVerified, state.journalChainValid]
        let flagText = flags.map { $0 ? "1" : "0" }.joined(separator: "|")
        let stagedText = state.stagedHashes?.joined(separator: ",") ?? "-"
        let previousText = state.previousHashes?.joined(separator: ",") ?? "-"
        let activeText = state.activeHashes?.joined(separator: ",") ?? "-"
        let pointerText = state.pointerHashes?.joined(separator: ",") ?? "-"
        let text = flagText + "|" + stagedText + "|" + previousText + "|" + activeText + "|" + pointerText
        return String(text.utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }, radix: 16)
    }
}
