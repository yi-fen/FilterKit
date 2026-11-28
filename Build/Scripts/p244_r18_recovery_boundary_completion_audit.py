from pathlib import Path
import sys
root = Path(__file__).resolve().parents[2]
smoke = (root / 'Build/scripts/p244_r18_recovery_boundary_completion.swift').read_text()
executor = (root / 'Sources/Environment/Helper/Execution/HelperRootAtomicActivationExecutor.swift').read_text()
checks = [
    ('R18 uses production Coordinator.prepare', 'coordinator.prepare(' in smoke),
    ('R18 uses real Previous preserve', 'previousStore.preserve(' in smoke),
    ('R18 uses real Staged stage', 'stagedStore.stage(' in smoke),
    ('R18 uses prepared activation API', 'prepared:preparedCase' in smoke),
    ('R18 uses durable recovery API', 'executor.recover(durableJournal:' in smoke),
    ('R18 schedules afterFirstProgressJournal', '"fault after first progress Journal"' in smoke),
    ('R18 schedules afterCommittedJournal', '"fault after committed Journal"' in smoke),
    ('R18 schedules beforePointerRename', '"fault before Pointer rename"' in smoke),
    ('R18 schedules afterPointerCommit', '"fault after Pointer commit"' in smoke),
    ('R18 schedules missing Previous backup case', '"missing Previous backup"' in smoke),
    ('Executor implements afterFirstProgressJournal injection', 'if faultAt == .afterFirstProgressJournal' in executor),
    ('Executor implements afterCommittedJournal injection', 'if faultAt == .afterCommittedJournal' in executor),
    ('Executor implements afterPointerCommit injection', 'if faultAt == .afterPointerCommit' in executor),
    ('Rollback preflight before mutation', executor.index('Validate the complete rollback set') < executor.index('record.phase = .rollingBack', executor.index('Validate the complete rollback set'))),
    ('Rollback read-after-write verifies all Active hashes before rolledBack', executor.index('Read-after-rollback acceptance') < executor.index('record.phase = .rolledBack', executor.index('Read-after-rollback acceptance'))),
    ('No launchctl service start in executor', 'launchctl' not in executor),
]
failed = [name for name, ok in checks if not ok]
for name, ok in checks:
    print(('PASS' if ok else 'FAIL') + ': ' + name)
print(f'RESULT: {len(checks)-len(failed)}/{len(checks)} static checks')
if failed:
    sys.exit(1)
