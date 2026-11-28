#!/usr/bin/env python3
"""R10 audit: verify production-shaped activation ordering and fail-closed boundaries."""
from pathlib import Path
root = Path(__file__).resolve().parents[2]
executor = (root/'Sources/Environment/Helper/Execution/HelperRootAtomicActivationExecutor.swift').read_text()
prepared = (root/'Sources/Environment/Helper/Runtime/HelperTrustedInstallerCoordinator.swift').read_text()
staged = (root/'Sources/Environment/Helper/Runtime/HelperInstallerStagedReleaseStore.swift').read_text()
previous = (root/'Sources/Environment/Helper/Runtime/HelperInstallerPreviousReleaseStore.swift').read_text()
journal = (root/'Sources/Environment/Helper/Runtime/HelperInstallerTransactionJournal.swift').read_text()
checks = {
 'production entry accepts immutable prepared proof': 'prepared: HelperPreparedRootInstall' in executor,
 'prepared proof initializer is fileprivate': 'fileprivate init(plan:' in prepared,
 'prepare verifies signed provisioning envelope': 'verifier.verify(envelope)' in prepared,
 'prepare validates provisioning payload': 'envelope.payload.validate()' in prepared,
 'prepare binds JBROOT': 'bundle.jbRootPath == plan.jbRootPath' in prepared,
 'prepare returns prepared proof only after artifact verification': 'return HelperPreparedRootInstall(' in prepared,
 'production entry binds prepared transaction id': 'prepared.initialJournal.transactionID == durableJournal.transactionID' in executor,
 'production entry binds action and release identity': 'prepared.initialJournal.action == durableJournal.action' in executor and 'prepared.release.releaseIdentifier == release.bundle.releaseIdentifier' in executor,
 'production entry binds generation': 'prepared.release.generation == release.bundle.generation' in executor,
 'envelope bytes self hash checked': 'SHA256Digest.hex(prepared.provisioningEnvelopeData) == prepared.provisioningEnvelopeSHA256' in executor,
 'activation requires staged journal intent': 'durableJournal.pendingOperation == .activateRelease' in executor,
 'staged real bytes reopened': 'stagedStore.loadVerifiedArtifactsForActivation' in executor,
 'staged exact bytes compared to prepared release': 'stagedBytes[artifact] == release.bytes[Self.mapArtifact(artifact)]' in executor,
 'staged bytes cryptographically reverified': 'HelperRootReleaseSet().verify(' in executor,
 'upgrade and repin require previous release store': 'guard let previousRelease, let previousStore' in executor,
 'previous real bytes reopened': 'previousStore.loadVerifiedArtifactsForActivation' in executor,
 'previous byte counts and hashes checked': 'previousRelease.byteCounts[artifact] == bytes.count' in executor,
 'install rejects unexpected previous evidence': 'release.expectedPreviousHashes.values.contains(where: { $0 != nil })' in executor,
 'transaction lock acquired before evidence preflight': executor.index('acquireTransactionLock(rootFD)') < executor.index('try preflight?()'),
 'durable journal reloaded inside lock': 'journalStore.load(transactionID: durableJournal.transactionID)' in executor,
 'observer challenge validated inside preflight': 'HelperInstallerAuthenticatedServiceObserver.validate' in executor,
 'observer must be stopped': 'observation.state == .stopped' in executor,
 'active pointer follows activated journal': executor.index('completed.apply(.activateRelease)') < executor.index('ActiveReleasePointerWriter(jbRootPath: root).write'),
 'active pointer verifies actual active hashes': 'hashAt(parent, leaf), observed == record.newHashes[mapped]' in executor,
 'pointer read-after-write verification before cleanup': executor.index('verifyPublishedPointer(record: record') < executor.index('backupName(id, item).withCString { unlinkat(parent, $0, 0) }'),
 'recovery checks committed active set': 'if record.phase == .committed' in executor,
 'recovery re-publishes and verifies pointer': 'verifyPublishedPointer(record: record' in executor[executor.index('func recoverInternal'):],
 'staged loader refuses symlink transaction directory': 'O_NOFOLLOW' in staged and 'openat(baseFD, $0' in staged,
 'previous loader refuses symlink transaction directory': 'O_NOFOLLOW' in previous,
 'staged loader verifies exact entry inventory': 'entryNames(directoryFD: directoryFD) == expectedEntryNames' in staged,
 'previous loader verifies exact entry inventory': 'entryNames(directoryFD: directoryFD) == expectedEntryNames' in previous,
 'journal supports explicit manual intervention': 'requireManualIntervention' in journal,
 'no production runtime wiring or launchd bootstrap': 'wired to HelperRuntime' in executor and 'launchctl' not in executor.lower(),
}
failed=[]
for label, ok in checks.items():
 print(('PASS' if ok else 'FAIL') + ': ' + label)
 if not ok: failed.append(label)
print(f'RESULT: {len(checks)-len(failed)}/{len(checks)} passed')
raise SystemExit(bool(failed))
