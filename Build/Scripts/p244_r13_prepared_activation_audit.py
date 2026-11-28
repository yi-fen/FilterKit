#!/usr/bin/env python3
from pathlib import Path
root = Path(__file__).resolve().parents[2]
coord = (root/'Sources/Environment/Helper/Runtime/HelperTrustedInstallerCoordinator.swift').read_text()
executor = (root/'Sources/Environment/Helper/Execution/HelperRootAtomicActivationExecutor.swift').read_text()
smoke = (root/'Build/scripts/p244_r13_prepared_activation_smoke.swift').read_text()
runner = (root/'Build/scripts/run_p244_r13_prepared_activation_smoke.sh').read_text()
checks = [
 ('Coordinator.prepare is compiled from production source', 'HelperTrustedInstallerCoordinator.swift' in runner),
 ('Atomic activation executor is compiled from production source', 'HelperRootAtomicActivationExecutor.swift' in runner),
 ('Prepared value initializer remains fileprivate', 'fileprivate init(plan:' in coord),
 ('prepare verifies provisioning signature', 'verifier.verify(envelope)' in coord),
 ('prepare validates provisioning payload', 'envelope.payload.validate()' in coord),
 ('prepare verifies exact release artifacts', 'HelperRootReleaseSet().verify' in coord),
 ('prepare binds envelope SHA-256', 'SHA256Digest.hex(provisioningEnvelopeData)' in coord),
 ('prepared activation overload exists', 'prepared: HelperPreparedRootInstall' in executor),
 ('prepared activation reloads staged bytes', 'loadVerifiedArtifactsForActivation' in executor),
 ('prepared activation compares staged bytes with prepared release', 'stagedBytes[artifact] == release.bytes' in executor),
 ('upgrade/repin requires Previous store', 'guard let previousRelease, let previousStore' in executor),
 ('prepared activation validates authenticated observer', 'HelperInstallerAuthenticatedServiceObserver.validate' in executor),
 ('prepared activation requires stopped service', 'observation.state == .stopped' in executor),
 ('journal state must be staged with activation intent', 'durableJournal.state == .staged' in executor and 'durableJournal.pendingOperation == .activateRelease' in executor),
 ('active pointer writer is compiled', 'HelperInstallerActiveReleasePointerWriter.swift' in runner),
 ('test uses deterministic signature checker', 'DeterministicTestSignatureChecker' in smoke),
 ('test rejects invalid test signature', 'invalid deterministic test signature is rejected' in smoke),
 ('test rejects stale observer challenge', 'stale observer challenge is rejected' in smoke),
 ('test rejects staged byte tampering', 'tampered staged bytes are rejected' in smoke),
 ('test verifies Journal reaches activated', 'Durable Journal reaches activated' in smoke),
 ('test verifies pointer transaction/release/generation binding', 'Active Pointer binds transaction, release and generation' in smoke),
 ('test verifies pointer hashes against all three Active files', 'Pointer hashes match all three independently observed Active files' in smoke),
 ('coordinator defaults to unavailable production installer', 'HelperUnavailableRootInstaller()' in coord and 'isProductionReady: Bool { false }' in coord),
]
failed = [name for name, ok in checks if not ok]
for name, ok in checks: print(('PASS' if ok else 'FAIL') + ': ' + name)
print(f'RESULT: {len(checks)-len(failed)}/{len(checks)} passed')
if failed: raise SystemExit(1)
