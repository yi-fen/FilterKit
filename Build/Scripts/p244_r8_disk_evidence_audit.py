#!/usr/bin/env python3
from pathlib import Path
import sys
root=Path(__file__).resolve().parents[2]
staged=(root/'Sources/Environment/Helper/Runtime/HelperInstallerStagedReleaseStore.swift').read_text()
previous=(root/'Sources/Environment/Helper/Runtime/HelperInstallerPreviousReleaseStore.swift').read_text()
executor=(root/'Sources/Environment/Helper/Execution/HelperRootAtomicActivationExecutor.swift').read_text()
test=(root/'Build/scripts/p244_r8_disk_evidence_smoke.swift').read_text()
checks={
 'Staged loader exists and takes transaction ID plus trusted expected hashes':'func loadVerifiedArtifactsForActivation(transactionID:' in staged and 'expectedHashes:' in staged,
 'Previous loader exists and takes transaction ID plus trusted expected hashes':'func loadVerifiedArtifactsForActivation(transactionID:' in previous and 'expectedHashes:' in previous,
 'Staged loader does not recursively acquire shared transaction lock':'func loadVerifiedArtifactsForActivation' in staged and 'not acquire another lock' in staged,
 'Previous loader does not recursively acquire shared transaction lock':'does not acquire HelperInstallerSharedTransactionLock' in previous,
 'Staged transaction directory opened with O_NOFOLLOW':'openat(baseFD, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)' in staged,
 'Previous backup directory opened with O_NOFOLLOW':'openat(backupRootFD, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)' in previous,
 'Staged directory inventory must exactly match expected names':'entryNames(directoryFD: directoryFD) == expectedEntryNames' in staged,
 'Previous directory inventory must exactly match expected names':'entryNames(directoryFD: directoryFD) == expectedEntryNames' in previous,
 'Staged reads reject non-regular, non-root-owned, linked or wrong-mode files':all(x in staged for x in ['S_IFREG','before.st_uid == 0','before.st_gid == 0','before.st_nlink == 1','before.st_mode & 0o777','O_NOFOLLOW']),
 'Previous reads reject non-regular, non-root-owned, linked or wrong-mode files':all(x in previous for x in ['S_IFREG','before.st_uid == 0','before.st_gid == 0','before.st_nlink == 1','before.st_mode & 0o777','O_NOFOLLOW']),
 'Staged read verifies pre/post descriptor identity':'FileIdentity(before) == FileIdentity(after)' in staged[staged.index('private func readArtifact'):staged.index('private func hashArtifact')],
 'Previous read verifies pre/post descriptor identity':'FileIdentity(before) == FileIdentity(after)' in previous[previous.index('private func readBackupArtifact'):previous.index('private func hashArtifact')],
 'Staged read enforces maximum artifact size':'maximumSize' in staged[staged.index('private func readArtifact'):staged.index('private func hashArtifact')],
 'Previous read enforces maximum artifact size':'maximum: Int64' in previous[previous.index('private func readBackupArtifact'):previous.index('private func hashArtifact')],
 'Activation obtains transaction lock before disk evidence preflight':'acquireTransactionLock(rootFD)' in executor and executor.index('acquireTransactionLock(rootFD)') < executor.index('try preflight?()'),
 'Activation binds Staged bytes to verified Release bytes':'stagedBytes[artifact] == release.bytes[Self.mapArtifact(artifact)]' in executor,
 'Activation validates Previous bytes against expected Active hashes':'previousRelease.hashes == expectedPrevious' in executor,
 'Host smoke compiles the actual two disk-store implementations':'HelperInstallerStagedReleaseStore.swift' in (root/'Build/scripts/run_p244_r8_disk_evidence_smoke.sh').read_text() and 'HelperInstallerPreviousReleaseStore.swift' in (root/'Build/scripts/run_p244_r8_disk_evidence_smoke.sh').read_text(),
 'Host smoke covers successful reads for both stores':'Staged loader reads exact three root-owned artifacts' in test and 'Previous loader reads exact three root-owned artifacts' in test,
 'Host smoke covers tampering and missing members':'rejects modified artifact bytes' in test and 'rejects missing member of three-file set' in test,
 'Host smoke covers unexpected entries':'rejects unexpected directory entry' in test,
 'Host smoke covers symlink and hardlink attacks':'rejects symlink artifact' in test and 'rejects hard-linked artifact' in test,
 'Host smoke covers permission and ownership violations':'rejects incorrect artifact mode' in test and 'rejects non-root-owned artifact' in test and 'writable transaction directory' in test,
 'Host smoke covers expected-hash mismatch':'rejects expected-hash mismatch' in test,
 'R8 remains test-only and does not enable production mutation':'productionMutationReleased = true' not in executor and 'launchctl' not in executor,
}
failed=[]
for label,ok in checks.items(): print(f"{'PASS' if ok else 'FAIL'}: {label}"); failed += [] if ok else [label]
print(f'RESULT: {len(checks)-len(failed)}/{len(checks)}')
sys.exit(1 if failed else 0)
