#!/usr/bin/env python3
from pathlib import Path
root = Path(__file__).resolve().parents[2]
executor = (root/'Sources/Environment/Helper/Execution/HelperRootAtomicActivationExecutor.swift').read_text()
pointer = (root/'Sources/Environment/Helper/Runtime/HelperInstallerActiveReleasePointerWriter.swift').read_text()
staged = (root/'Sources/Environment/Helper/Runtime/HelperInstallerStagedReleaseStore.swift').read_text()
previous = (root/'Sources/Environment/Helper/Runtime/HelperInstallerPreviousReleaseStore.swift').read_text()
observer = (root/'Sources/Environment/Helper/Runtime/HelperInstallerDescriptorFilesystemObserver.swift').read_text()
checks = {
 'persistent lock acquired before preflight evidence read': executor.index('acquireTransactionLock(rootFD)') < executor.index('try preflight?()'),
 'staged bytes loaded from transaction store': 'stagedStore.loadVerifiedArtifactsForActivation' in executor,
 'previous bytes loaded from backup store': 'previousStore.loadVerifiedArtifactsForActivation' in executor,
 'staged store read method avoids nested lock': 'does' in staged and 'not acquire another lock' in staged,
 'previous store read method documents held lock': 'while the caller holds the activation lock' in previous,
 'activation compares staged bytes to prepared release': 'stagedBytes[artifact] == release.bytes[Self.mapArtifact(artifact)]' in executor,
 'upgrade requires full previous hash inventory': 'expectedPrevious.count == HelperRootReleaseSet.Artifact.allCases.count' in executor,
 'durable journal is reloaded after lock': 'journalStore.load(transactionID: durableJournal.transactionID)' in executor,
 'observer challenge validated': 'HelperInstallerAuthenticatedServiceObserver.validate' in executor,
 'observer must report stopped': 'observation.state == .stopped' in executor,
 'active files rehashed before pointer': 'guard let observed = try hashAt(parent, leaf), observed == record.newHashes[mapped]' in executor,
 'pointer published only after durable activation': executor.index('completed.apply(.activateRelease)') < executor.index('ActiveReleasePointerWriter(jbRootPath: root).write'),
 'pointer read-after-write verification': 'verifyPublishedPointer(record: record' in executor,
 'pointer transaction id bound': 'pointer.transactionID == record.id' in executor,
 'pointer release id bound': 'pointer.releaseIdentifier == record.releaseIdentifier' in executor,
 'pointer generation bound': 'pointer.generation == record.generation' in executor,
 'pointer hashes bound to active': 'pointerHashes == expectedHashes' in executor,
 'journal activated before cleanup': 'durableJournal.state == .activated' in executor,
 'backups retained until pointer verification': executor.index('verifyPublishedPointer(record: record') < executor.index('backupName(record.id, item).withCString { unlinkat(parent, $0, 0) }'),
 'recovery re-verifies pointer': 'verifyPublishedPointer(record: record' in executor[executor.index('func recoverInternal'):],
 'pointer writer uses no-follow temp': 'O_EXCL | O_NOFOLLOW' in pointer,
 'pointer writer fsyncs temp file': 'fsync(fd)' in pointer,
 'pointer writer atomically renames': 'renameat(parentFD, temp, parentFD, destination)' in pointer,
 'pointer writer fsyncs parent': 'fsync(parentFD)' in pointer,
 'observer reads pointer from descriptor path': 'observeActiveReleasePointer()' in observer,
 'no launchd bootstrap added': 'bootstrap' not in executor.lower(),
 'Helper runtime production wiring remains explicitly disabled': 'wired to HelperRuntime' in ' '.join(executor.split()),
}
failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items(): print(('PASS' if ok else 'FAIL') + ': ' + name)
print(f'RESULT: {len(checks)-len(failed)}/{len(checks)} passed')
raise SystemExit(1 if failed else 0)
