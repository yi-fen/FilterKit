#!/usr/bin/env python3
"""R11 audit: prepared activation trust chain, ordering, and explicit E2E limitations."""
from pathlib import Path
root = Path(__file__).resolve().parents[2]
executor = (root/'Sources/Environment/Helper/Execution/HelperRootAtomicActivationExecutor.swift').read_text()
coordinator = (root/'Sources/Environment/Helper/Runtime/HelperTrustedInstallerCoordinator.swift').read_text()
staged = (root/'Sources/Environment/Helper/Runtime/HelperInstallerStagedReleaseStore.swift').read_text()
previous = (root/'Sources/Environment/Helper/Runtime/HelperInstallerPreviousReleaseStore.swift').read_text()
journal = (root/'Sources/Environment/Helper/Runtime/HelperInstallerTransactionJournal.swift').read_text()
active_pointer = (root/'Sources/Environment/Helper/Runtime/HelperInstallerActiveReleasePointerWriter.swift').read_text()
checks = {
 'prepared proof has fileprivate initializer': 'fileprivate init(plan:' in coordinator,
 'prepare decodes signed envelope': 'JSONDecoder().decode(HelperSignedProvisioningManifest.self' in coordinator,
 'prepare invokes signature verifier': 'verifier.verify(envelope)' in coordinator,
 'prepare validates payload': 'envelope.payload.validate()' in coordinator,
 'prepare binds envelope JBROOT to plan': 'bundle.jbRootPath == plan.jbRootPath' in coordinator,
 'prepare verifies exact artifact set': 'HelperRootReleaseSet().verify(bundle: bundle' in coordinator,
 'prepared proof binds envelope digest': 'provisioningEnvelopeSHA256: SHA256Digest.hex(provisioningEnvelopeData)' in coordinator,
 'default installer remains unavailable': 'HelperUnavailableRootInstaller()' in coordinator,
 'execution gate blocks non-ready backend': 'rootInstallerAvailable: rootInstaller.isProductionReady && trustedProvisioningStore != nil' in coordinator,
 'prepared activation API is present': 'prepared: HelperPreparedRootInstall' in executor,
 'prepared JBROOT bound to executor root': 'prepared.plan.jbRootPath == self.root' in executor,
 'prepared transaction identity bound': 'prepared.initialJournal.transactionID == durableJournal.transactionID' in executor,
 'prepared action and journal identity bound': 'prepared.initialJournal.action == durableJournal.action' in executor,
 'prepared release ID and generation bound': 'prepared.release.releaseIdentifier == release.bundle.releaseIdentifier' in executor and 'prepared.release.generation == release.bundle.generation' in executor,
 'provisioning envelope bytes rehashed': 'SHA256Digest.hex(prepared.provisioningEnvelopeData) == prepared.provisioningEnvelopeSHA256' in executor,
 'durable journal requires staged activate intent': 'durableJournal.state == .staged' in executor and 'durableJournal.pendingOperation == .activateRelease' in executor,
 'staged artifacts read from actual store': 'stagedStore.loadVerifiedArtifactsForActivation' in executor,
 'staged bytes reverified against signed bundle': 'HelperRootReleaseSet().verify(' in executor,
 'staged bytes compared exactly to release payload': 'stagedBytes[artifact] == release.bytes[Self.mapArtifact(artifact)]' in executor,
 'upgrade requires verified previous release and store': 'guard let previousRelease, let previousStore' in executor,
 'previous artifacts read from actual store': 'previousStore.loadVerifiedArtifactsForActivation' in executor,
 'previous byte count and digest rechecked': 'previousRelease.byteCounts[artifact] == bytes.count' in executor,
 'install rejects unexpected previous evidence': 'release.expectedPreviousHashes.values.contains(where: { $0 != nil })' in executor,
 'persistent transaction lock precedes preflight': executor.index('acquireTransactionLock(rootFD)') < executor.index('try preflight?()'),
 'journal reloaded after lock acquisition': 'journalStore.load(transactionID: durableJournal.transactionID)' in executor,
 'authenticated observer challenge validated': 'HelperInstallerAuthenticatedServiceObserver.validate' in executor,
 'observer must report stopped': 'observation.state == .stopped' in executor,
 'active pointer writer atomically publishes': 'renameat' in active_pointer and 'fsync' in active_pointer,
 'active pointer bound to transaction and generation': 'transactionID' in active_pointer and 'generation' in active_pointer,
 'journal supports explicit manual intervention': 'requireManualIntervention' in journal,
 'staged store rejects symlink paths': 'O_NOFOLLOW' in staged,
 'previous store rejects symlink paths': 'O_NOFOLLOW' in previous,
 'production execution remains unconnected to runtime': 'not wired to HelperRuntime' in executor or 'wired to HelperRuntime or the production deployment backend' in executor,
}
failed=[]
for label, ok in checks.items():
    print(('PASS' if ok else 'FAIL') + ': ' + label)
    if not ok: failed.append(label)
print(f'RESULT: {len(checks)-len(failed)}/{len(checks)} passed')
# Explicitly surface the current limitation: audit does not execute prepared overload.
print('LIMITATION: this static audit does not execute the prepared overload end-to-end.')
raise SystemExit(bool(failed))
