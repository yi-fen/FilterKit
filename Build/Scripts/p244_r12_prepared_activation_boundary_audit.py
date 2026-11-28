#!/usr/bin/env python3
"""R12 source-boundary audit; not a substitute for the deferred full E2E run."""
from pathlib import Path
import sys
root = Path(__file__).resolve().parents[2]
executor = (root/'Sources/Environment/Helper/Execution/HelperRootAtomicActivationExecutor.swift').read_text()
coordinator = (root/'Sources/Environment/Helper/Runtime/HelperTrustedInstallerCoordinator.swift').read_text()
staged = (root/'Sources/Environment/Helper/Runtime/HelperInstallerStagedReleaseStore.swift').read_text()
previous = (root/'Sources/Environment/Helper/Runtime/HelperInstallerPreviousReleaseStore.swift').read_text()
journal = (root/'Sources/Environment/Helper/Runtime/HelperInstallerTransactionJournal.swift').read_text()
checks = []
def has(label, text, needle): checks.append((label, needle in text))
def before(label, text, first, second):
    checks.append((label, first in text and second in text and text.index(first) < text.index(second)))
# Prepared hand-off and immutable provenance.
has('Prepared install initializer remains file-scoped', coordinator, 'fileprivate init(')
has('Coordinator verifies signed envelope before returning prepared value', coordinator, 'try verifier.verify(envelope)')
has('Coordinator validates provisioning payload', coordinator, 'try envelope.payload.validate()')
has('Coordinator verifies exact artifact release set', coordinator, 'HelperRootReleaseSet().verify')
has('Coordinator binds verified release identifier', coordinator, 'verified.releaseIdentifier == bundle.releaseIdentifier')
has('Coordinator binds verified generation', coordinator, 'verified.generation == bundle.generation')
has('Coordinator hashes exact envelope bytes', coordinator, 'SHA256Digest.hex(provisioningEnvelopeData)')
has('Execution gate remains in coordinator', coordinator, 'gate.blockReason(plan: prepared.plan')
has('Default installer remains unavailable', coordinator, 'HelperUnavailableRootInstaller()')
# Prepared activation tuple is re-bound before disk reads.
for needle, label in [
 ('prepared.plan.jbRootPath == self.root','Prepared root matches executor root'),
 ('prepared.initialJournal.transactionID == durableJournal.transactionID','Prepared transaction ID matches Journal'),
 ('prepared.initialJournal.action == durableJournal.action','Prepared action matches Journal'),
 ('prepared.initialJournal.releaseIdentifier == durableJournal.releaseIdentifier','Prepared release ID matches Journal'),
 ('prepared.initialJournal.generation == durableJournal.generation','Prepared generation matches Journal'),
 ('durableJournal.state == .staged','Journal must be staged'),
 ('durableJournal.pendingOperation == .activateRelease','Journal must carry activation intent'),
 ('SHA256Digest.hex(prepared.provisioningEnvelopeData) == prepared.provisioningEnvelopeSHA256','Envelope bytes are rehashed'),
 ('JSONDecoder().decode(\n                    HelperSignedProvisioningManifest.self','Envelope is decoded again at activation'),
 ('envelope.payload.jbRootPath == self.root','Envelope root is rebound'),
 ('envelope.payload.releaseIdentifier == release.bundle.releaseIdentifier','Envelope release ID is rebound'),
 ('envelope.payload.generation == release.bundle.generation','Envelope generation is rebound'),
 ('envelope.payload.helperCDHash == release.bundle.helperCDHash','Envelope Helper CDHash is rebound'),
 ('envelope.payload.teamIdentifier == release.bundle.teamIdentifier','Envelope Team ID is rebound'),
 ('try prepared.initialJournal.validateChain()','Prepared Journal chain is revalidated'),
 ('expectedDigestMap[digest.relativePath] == nil','Duplicate digest paths are rejected without Dictionary trap'),
 ('expectedDigestMap.count == HelperRootReleaseSet.Artifact.allCases.count','Digest inventory must be exact'),
 ('expected == actual','Expected digests match prepared release hashes'),
 ('stagedStore.loadVerifiedArtifactsForActivation(','Staged bytes are reopened from disk'),
 ('previousStore.loadVerifiedArtifactsForActivation(','Previous bytes are reopened from disk'),
 ('stagedBytes[artifact] == release.bytes[Self.mapArtifact(artifact)]','Staged bytes equal release bytes'),
 ('previousRelease.byteCounts[artifact] == bytes.count','Previous byte count is checked'),
 ('persisted == durableJournal','Durable Journal is reloaded and compared'),
 ('HelperInstallerAuthenticatedServiceObserver.validate(','Observer report is authenticated'),
 ('observation.state == .stopped','Helper must be stopped'),
 ('preflight: evidenceCheck','Evidence checks are passed as locked preflight'),
]: has(label, executor, needle)
# Lock ordering and store hardening.
activation = executor[executor.index('private func activateInternal'):executor.index('private func ' , executor.index('private func activateInternal')+20)]
before('Process lock acquired before preflight', activation, 'Self.lock.lock()', 'try preflight?()')
before('Persistent root lock acquired before preflight', activation, 'acquireTransactionLock(rootFD)', 'try preflight?()')
has('Staged store uses O_NOFOLLOW for transaction directory', staged, 'O_DIRECTORY | O_NOFOLLOW')
has('Previous store uses O_NOFOLLOW for transaction directory', previous, 'O_DIRECTORY | O_NOFOLLOW')
has('Staged store rejects unexpected entries', staged, 'entryNames(directoryFD: transactionFD) == expectedEntryNames')
has('Previous store rejects unexpected entries', previous, 'entryNames(directoryFD: directoryFD) == expectedEntryNames')
has('Journal exposes hash-chain validation', journal, 'func validateChain() throws')
failed = [label for label, ok in checks if not ok]
for label, ok in checks:
    print(('PASS' if ok else 'FAIL') + ': ' + label)
print(f'RESULT: {len(checks)-len(failed)}/{len(checks)}')
if failed: sys.exit(1)
