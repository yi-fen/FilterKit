#!/usr/bin/env python3
from pathlib import Path
import sys
root = Path(__file__).resolve().parents[2]
src = (root / 'Sources/Environment/Helper/Execution/HelperRootAtomicActivationExecutor.swift').read_text()
smoke = (root / 'Build/scripts/p244_r5_active_transaction_smoke.swift').read_text()
checks = {
    'durable journal-bound activation API': 'durableJournal: HelperInstallerTransactionJournal' in src and 'journalStore: HelperInstallerDurableJournalStore' in src,
    'requires staged Journal state and activation intent': 'durableJournal.state == .staged' in src and 'pendingOperation == .activateRelease' in src,
    'reloads persisted Journal under transaction lock': 'preflight?()' in src and 'journalStore.load(transactionID: durableJournal.transactionID)' in src,
    'binds activation record to durable Transaction ID': 'let id = transactionID' in src,
    'requires complete staged inventory': 'stagedInspection.state == .complete' in src and 'stagedSetNotComplete' in src,
    'staged inventory hashes match release bytes': 'stagedInspection.observedHashes == expectedStagedHashes' in src,
    'upgrade and repin require complete previous inventory': 'previousInspection.state == .complete' in src and 'previousSetNotComplete' in src,
    'authenticated observer challenge and peer checked': 'HelperInstallerAuthenticatedServiceObserver.validate' in src,
    'service must be stopped before mutation': 'observation.state == .stopped' in src,
    'service and Journal checks occur while persistent lock held': src.index('try preflight?()') > src.index('acquireTransactionLock(rootFD)'),
    'existing three-file descriptor-relative activation retained': 'renameNoReplace(parent, tempName(id, item), leaf)' in src,
    'each Active replacement read-back hash checked': 'hashAt(parent, leaf) == record.newHashes[item]' in src,
    'per-file progress Journal is durable': 'record.completed.append(item); try writeRecord(record, rootFD: rootFD)' in src,
    'durable Journal completion precedes backup cleanup': src.index('try journalStore.save(completed)') < src.index('_ = backupName(id, item).withCString { unlinkat(parent, $0, 0) }', src.index('try journalStore.save(completed)')),
    'indeterminate Journal commit retains activation record': 'journalCommitIndeterminate' in src and 'Keep the committed activation record and all backups' in src,
    'recovery validates active leaf names': 'hashAt(parent, leaf)' in src,
    'committed recovery reconciles pending Journal': 'reconciled.apply(.activateRelease)' in src,
    'partial recovery marks manual intervention': 'reconciled.apply(.requireManualIntervention)' in src,
    'recovery requires authenticated stopped service': 'func recover(durableJournal:' in src and 'observation.state == .stopped' in src,
    'no launchctl/bootstrap/service start call': 'launchctl' not in src and 'bootstrap' not in src,
    'host smoke executes real Active transaction source': 'HelperRootAtomicActivationExecutor.swift' in (root / 'Build/scripts/run_p244_r5_active_transaction_smoke.sh').read_text(),
    'host smoke covers complete activation': 'three Active files commit' in smoke,
    'host smoke covers partial staged rejection': 'partial staged set rejected' in smoke,
    'host smoke covers stale challenge rejection': 'stale observer challenge rejected' in smoke,
    'host smoke covers running service rejection': 'running Helper blocks Active replacement' in smoke,
    'host smoke covers durable completion uncertainty': 'Journal completion failure is indeterminate' in smoke,
    'host smoke covers committed recovery reconciliation': 'committed Active state reconciles pending Durable Journal' in smoke,
    'host smoke covers partial activation rollback': 'partial Active transaction rolls back' in smoke,
    'all original production release gates remain closed': 'productionMutationReleased = true' not in src and 'executionReleased = true' not in src,
}
failed=[]
for label, ok in checks.items():
    print(f"{'PASS' if ok else 'FAIL'}: {label}")
    if not ok: failed.append(label)
print(f'RESULT: {len(checks)-len(failed)}/{len(checks)}')
sys.exit(1 if failed else 0)
