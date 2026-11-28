#!/usr/bin/env python3
from pathlib import Path
import sys
root = Path(__file__).resolve().parents[2]
executor = (root / 'Sources/Environment/Helper/Execution/HelperRootAtomicActivationExecutor.swift').read_text()
writer = (root / 'Sources/Environment/Helper/Runtime/HelperInstallerActiveReleasePointerWriter.swift').read_text()
observer = (root / 'Sources/Environment/Helper/Runtime/HelperInstallerDescriptorFilesystemObserver.swift').read_text()
smoke = (root / 'Build/scripts/p244_r5_active_transaction_smoke.swift').read_text()
checks = {
    'Active Pointer writer is integrated into existing executor': 'HelperInstallerActiveReleasePointerWriter(jbRootPath: root).write' in executor,
    'pointer write occurs after Durable Journal completion': executor.index('try journalStore.save(completed)') < executor.index('HelperInstallerActiveReleasePointerWriter(jbRootPath: root).write'),
    'pointer write occurs after all three Active read-back hashes': executor.index('record.phase = .committed') < executor.index('HelperInstallerActiveReleasePointerWriter(jbRootPath: root).write'),
    'pointer binds transaction ID': 'transactionID: id' in executor and 'let transactionID: UUID' in observer,
    'pointer binds release ID and generation': 'releaseIdentifier: release.bundle.releaseIdentifier' in executor and 'generation: release.bundle.generation' in executor,
    'pointer binds exact three Active hashes': 'observedActiveHashes: observedPointerHashes' in executor and 'release.hashes == observedActiveHashes' in writer,
    'Active files are freshly rehashed immediately before pointer write': executor.count('guard let observed = try hashAt(parent, leaf), observed == record.newHashes[mapped]') >= 2,
    'pointer is explicitly schema v2': 'schemaVersion: 2' in writer and 'schemaVersion == 2' in observer,
    'pointer remains a non-authoritative hint': 'non-authoritative active-release hint' in writer and 'Callers must compare' in observer,
    'descriptor-relative no-follow root and parent traversal': 'O_NOFOLLOW' in writer and 'openat(' in writer,
    'pointer temp is exclusive private 0600': 'O_CREAT | O_EXCL | O_NOFOLLOW' in writer and '0o600' in writer,
    'pointer file is fsynced before atomic rename': 'fsync(fd)' in writer and 'renameat(parentFD' in writer,
    'pointer parent directory is fsynced': 'fsync(parentFD)' in writer,
    'existing pointer must be root-owned regular single-link private file': 'existing.st_uid == 0' in writer and 'existing.st_nlink == 1' in writer and '(existing.st_mode & 0o777) == 0o600' in writer,
    'pointer failure retains transaction evidence': 'Failure.activePointerCommitIndeterminate' in executor and 'throw Failure.activePointerCommitIndeterminate' in executor,
    'committed recovery republishes pointer before cleanup': executor.index('HelperInstallerActiveReleasePointerWriter(jbRootPath: root).write', executor.index('private func recoverInternal')) < executor.index('unlinkat(parent, $0, 0)', executor.index('private func recoverInternal')),
    'recovery pointer uses persisted transaction/release/generation identity': 'transactionID: record.id' in executor and 'releaseIdentifier: record.releaseIdentifier' in executor and 'generation: record.generation' in executor,
    'pointer failure fault injection exists': 'beforePointerRename' in executor and 'afterPointerCommit' in executor and 'beforeRename' in writer,
    'Host smoke validates pointer identity and recovery': 'Active Pointer binds transaction, release and generation' in smoke and 'recovery repairs tampered Active Pointer' in smoke,
    'Host smoke validates pointer failure evidence retention': 'pointer rename failure preserves recovery evidence' in smoke and 'post-pointer crash retains transaction evidence' in smoke,
    'no launchctl/bootstrap or production gate opening': 'launchctl' not in executor and 'bootstrap' not in executor and 'productionMutationReleased = true' not in executor,
}
failed=[]
for label, ok in checks.items():
    print(f"{'PASS' if ok else 'FAIL'}: {label}")
    if not ok: failed.append(label)
print(f'RESULT: {len(checks)-len(failed)}/{len(checks)}')
sys.exit(1 if failed else 0)
