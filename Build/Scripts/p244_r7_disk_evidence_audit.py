#!/usr/bin/env python3
from pathlib import Path
import sys
root = Path(__file__).resolve().parents[2]
executor = (root / 'Sources/Environment/Helper/Execution/HelperRootAtomicActivationExecutor.swift').read_text()
staged = (root / 'Sources/Environment/Helper/Runtime/HelperInstallerStagedReleaseStore.swift').read_text()
previous = (root / 'Sources/Environment/Helper/Runtime/HelperInstallerPreviousReleaseStore.swift').read_text()
checks = {
    'R7 exposes activation API using prepared install and disk stores': 'prepared: HelperPreparedRootInstall' in executor and 'stagedStore: HelperInstallerStagedReleaseStore' in executor and 'previousStore: HelperInstallerPreviousReleaseStore?' in executor,
    'R7 activation API does not accept caller-supplied Inspection evidence': 'stagedInspection:' not in executor[executor.index('func activate(_ release: Release,', executor.index('Production-shaped activation entry point')):executor.index('private func activateInternal')],
    'staged artifact loader is transaction scoped': 'loadVerifiedArtifactsForActivation(transactionID:' in staged,
    'previous artifact loader is transaction scoped': 'loadVerifiedArtifactsForActivation(transactionID:' in previous,
    'staged loader opens transaction directory without following symlinks': 'O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC' in staged[staged.index('func loadVerifiedArtifactsForActivation'):staged.index('func inspect(prepared:')],
    'previous loader opens transaction directory without following symlinks': 'O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC' in previous[previous.index('func loadVerifiedArtifactsForActivation'):previous.index('func inspect(transactionID:')],
    'staged loader requires exact three-entry inventory': 'entryNames(directoryFD: directoryFD) == expectedEntryNames' in staged,
    'previous loader requires exact three-entry inventory': 'entryNames(directoryFD: directoryFD) == expectedEntryNames' in previous,
    'staged loader validates all three hashes against trusted expected hashes': 'SHA256Digest.hex(bytes) == expected' in staged[staged.index('func loadVerifiedArtifactsForActivation'):staged.index('func inspect(prepared:')],
    'previous loader validates all three hashes against trusted expected hashes': 'SHA256Digest.hex(bytes) == expected' in previous[previous.index('func loadVerifiedArtifactsForActivation'):previous.index('func inspect(transactionID:')],
    'staged file reads enforce root ownership, single link, mode and file identity': 'before.st_uid == 0' in staged and 'before.st_nlink == 1' in staged and 'FileIdentity(before) == FileIdentity(after)' in staged,
    'previous file reads enforce root ownership, single link, mode, no set-id bits and file identity': 'before.st_uid == 0' in previous and 'before.st_nlink == 1' in previous and '(before.st_mode & 0o6000) == 0' in previous and 'FileIdentity(before) == FileIdentity(after)' in previous,
    'staged artifacts are re-verified against signed release bundle digests': 'HelperRootReleaseSet().verify(' in executor and 'expectedDigests: release.expectedDigests' in executor,
    'staged bytes must equal the release bytes used by activation': 'stagedBytes[artifact] == release.bytes[Self.mapArtifact(artifact)]' in executor,
    'previous inventory hashes must match the expected previous Active hashes': 'previousRelease.hashes == expectedPrevious' in executor,
    'durable Journal binds prepared action, release ID and generation': 'prepared.initialJournal.action == durableJournal.action' in executor and 'durableJournal.releaseIdentifier == release.bundle.releaseIdentifier' in executor and 'durableJournal.generation == release.bundle.generation' in executor,
    'caller-supplied Inspection overload is deprecated': 'caller-supplied Inspection is compatibility-only' in executor,
    'previous byte counts and hashes are checked against disk bytes': 'previousRelease.byteCounts[artifact] == bytes.count' in executor and 'SHA256Digest.hex(bytes) == previousRelease.hashes[artifact]' in executor,
    'install path rejects unexpected previous-release evidence': 'previousRelease != nil || previousStore != nil' in executor,
    'upgrade/repin requires both previous inventory and previous store': 'guard let previousRelease, let previousStore' in executor,
    'disk evidence check runs as activation preflight': 'preflight: evidenceCheck' in executor,
    'activation lock is acquired before preflight executes': executor.index('acquireTransactionLock(rootFD)') < executor.index('try preflight?()'),
    'staged and previous loaders explicitly avoid nested transaction lock': 'not acquire another lock' in staged and 'does not acquire HelperInstallerSharedTransactionLock' in previous,
    'legacy inspection-based API remains marked as compatibility path': 'Legacy journal-bound activation' in executor or 'Legacy' in executor[:executor.index('Production-shaped activation entry point')],
    'R7 does not enable launchd or production mutation': 'launchctl' not in executor and 'productionMutationReleased = true' not in executor,
}
failed=[]
for label, ok in checks.items():
    print(f"{'PASS' if ok else 'FAIL'}: {label}")
    if not ok: failed.append(label)
print(f'RESULT: {len(checks)-len(failed)}/{len(checks)}')
sys.exit(1 if failed else 0)
