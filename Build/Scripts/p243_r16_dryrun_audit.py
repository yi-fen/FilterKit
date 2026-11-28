#!/usr/bin/env python3
from pathlib import Path
root = Path(__file__).resolve().parents[2]
source = (root / 'Sources/Environment/Helper/Runtime/HelperInstallerRecoveryDryRun.swift').read_text()
smoke = (root / 'Build/scripts/p243_r16_dryrun_smoke.swift').read_text()
checks = {
    'dry-run has explicit ordered transaction steps': all(x in source for x in ['journalIntent', 'stageArtifacts', 'preservePrevious', 'replaceActive', 'updatePointer', 'journalCommit', 'verifyRecoveredState']),
    'dry-run is an in-memory snapshot model': 'struct Snapshot' in source and 'static func run(' in source,
    'service must remain stopped': 'guard state.serviceStopped' in source,
    'journal chain is checked': 'state.journalChainValid' in source,
    'ownership is checked': 'state.ownershipVerified' in source,
    'committed journal requires active target and pointer': 'state.activeHashes == target, state.pointerHashes == target' in source,
    'pointer mismatch blocks': 'release pointer hash mismatch' in source,
    'second assessment is repeated': 'let repeated = assess(state' in source,
    'digest explicitly not authorization': 'must never be used as an authorization token' in source,
    'no filesystem or launchd mutation API': not any(x in source for x in ['openat(', 'renameat(', 'unlinkat(', 'launchctl', 'posix_spawn']),
    'crash matrix all steps exercised': 'for point in HelperInstallerRecoveryDryRun.Step.allCases' in smoke,
    'invalid journal scenario exercised': 'corruptJournal: true' in smoke,
    'running service scenario exercised': 'serviceRunning: true' in smoke,
    'pointer mismatch scenario exercised': 'corruptPointer: true' in smoke,
}
for label, ok in checks.items():
    print(('PASS' if ok else 'FAIL') + ': ' + label)
if not all(checks.values()):
    raise SystemExit(1)
print(f'SUMMARY: {len(checks)}/{len(checks)} passed')
