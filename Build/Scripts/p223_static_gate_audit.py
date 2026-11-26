#!/usr/bin/env python3
from pathlib import Path
root = Path(__file__).resolve().parents[2]
checks = []
def check(name, condition):
    checks.append((name, bool(condition)))
store = (root/'Sources/Environment/Helper/Execution/HelperDeploymentDurableLedgerStore.swift').read_text()
ledger = (root/'Sources/Environment/Helper/Execution/HelperDeploymentIdempotencyLedger.swift').read_text()
runtime = (root/'Sources/Environment/Helper/Runtime/HelperRuntime.swift').read_text()
dispatch = (root/'Sources/Environment/Helper/Runtime/HelperRequestDispatcher.swift').read_text()
executor = (root/'Sources/Environment/Helper/Execution/HelperSafeFileExecutor.swift').read_text()
check('root-owned directory validation', 'st.st_uid == 0' in store and 'st.st_gid == 0' in store)
check('root-owned 0600 ledger validation', 'st.st_mode & 0o777) == 0o600' in store)
check('no-follow file access', 'O_NOFOLLOW' in store)
check('atomic replace and fsync', 'renameat(dir, t, dir, dst)' in store and 'fsync(dir)' in store)
check('bounded record count and bytes', 'records.count <= 256' in store and 'maximumBytes' in store)
check('restart converts in-flight to indeterminate', 'case .inProgress: state = .indeterminate' in ledger)
check('runtime injects durable ledger', 'HelperDeploymentDurableLedgerStore' in runtime and 'durableStore: durableLedgerStore' in runtime)
check('reservation occurs after execution gate', dispatch.index('guard Self.executionReleased') < dispatch.index('deploymentIdempotencyLedger.begin'))
check('uncertain execution is persisted', 'state: .indeterminate' in dispatch)
check('automatic startup file recovery remains inspection-only', 'inspectPendingJournal' in (root/'Sources/Environment/Helper/Runtime/HelperStartupRecoveryCheck.swift').read_text())
for name, ok in checks:
    print(('PASS' if ok else 'FAIL') + ' ' + name)
print(f'{sum(ok for _,ok in checks)}/{len(checks)} passed')
raise SystemExit(0 if all(ok for _,ok in checks) else 1)
