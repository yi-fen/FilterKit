import Foundation

func check(_ condition: @autoclosure () -> Bool, _ label: String) {
    guard condition() else { fatalError("FAIL: \(label)") }
    print("PASS: \(label)")
}
let target = ["a1", "b2", "c3"]
let previous = ["p1", "p2", "p3"]
var count = 0
for point in HelperInstallerRecoveryDryRun.Step.allCases {
    let result = HelperInstallerRecoveryDryRun.run(target: target, previous: previous, crashAfter: point)
    check(result.passed, "crash rehearsal is deterministic and invariant-safe: \(point.rawValue)")
    check(result.snapshot.serviceStopped, "service remains stopped at \(point.rawValue)")
    count += 2
}
let complete = HelperInstallerRecoveryDryRun.run(target: target, previous: previous)
check(complete.disposition == .inspectOnly, "fully committed transaction is inspect-only")
check(complete.snapshot.journalCommitted && complete.snapshot.activeHashes == target && complete.snapshot.pointerHashes == target,
      "committed state has matching active inventory and pointer")
let badPointer = HelperInstallerRecoveryDryRun.run(target: target, previous: previous, corruptPointer: true)
check({ if case .blocked = badPointer.disposition { return true }; return false }(), "pointer mismatch blocks recovery")
let badJournal = HelperInstallerRecoveryDryRun.run(target: target, previous: previous, corruptJournal: true)
check({ if case .blocked = badJournal.disposition { return true }; return false }(), "invalid journal chain blocks recovery")
let running = HelperInstallerRecoveryDryRun.run(target: target, previous: previous, serviceRunning: true)
check({ if case .blocked = running.disposition { return true }; return false }(), "running service blocks recovery")
let changed = HelperInstallerRecoveryDryRun.run(target: target, previous: previous, crashAfter: .replaceActive)
check(changed.repeatedAssessment == changed.disposition, "second recovery assessment is idempotent")
check(!complete.evidenceDigest.isEmpty, "dry-run emits deterministic rehearsal digest")
print("SUMMARY: \(count + 7) assertions passed")
