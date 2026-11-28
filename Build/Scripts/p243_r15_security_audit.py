#!/usr/bin/env python3
from pathlib import Path
root = Path(__file__).resolve().parents[2]
lock = (root / 'Sources/Environment/Helper/Runtime/HelperInstallerSharedTransactionLock.swift').read_text()
accept = (root / 'Sources/Environment/Helper/Runtime/HelperReleaseAcceptanceLock.swift').read_text()
executor = (root / 'Sources/Environment/Helper/Execution/HelperRootAtomicActivationExecutor.swift').read_text()
preflight = (root / 'Sources/Environment/Helper/Runtime/HelperInstallerRecoveryPreflight.swift').read_text()
auth = (root / 'Sources/Environment/Helper/Runtime/HelperInstallerAuthenticatedServiceObserver.swift').read_text()
authorization = (root / 'Sources/Environment/Helper/Runtime/HelperInstallerRecoveryAuthorization.swift').read_text()
matrix = (root / 'Sources/Environment/Helper/Runtime/HelperInstallerCrashInjectionMatrix.swift').read_text()
checks = {
 'shared recovery lock delegates to existing persistent acceptance lock': 'HelperReleaseAcceptanceLock.withLock(root: jbroot' in lock,
 'installer uses same persistent lock inode name': '.filterkit-root-activation.lock' in executor,
 'acceptance lock uses same persistent lock inode name': '.filterkit-root-activation.lock' in accept,
 'evidence passes run while exclusive lock held': 'withExclusiveLock(jbroot: jbroot)' in preflight,
 'service observation reacquired independently for both passes': preflight.count('serviceObservation()') >= 2,
 'evidence equality enforced under lock': 'requireUnchangedEvidence(firstEvidence, secondEvidence)' in preflight,
 'observer challenge nonce checked': 'report.challenge == expectedChallenge' in auth,
 'observer peer identity requires kernel audit token digest': 'auditTokenDigest.map(HelperPolicy.isValidHash) == true' in auth,
 'observer code identity and team/bundle identity pinned': 'codeSigningIdentityMatches' in auth and 'pin.observerCodeIdentitySHA256' in auth,
 'running helper identity checked by existing observation contract': 'report.observation.validates(' in auth,
 'review approval cannot authorize execution': 'executionNotAvailable' in authorization and 'throw AuthorizationError.executionNotAvailable' in authorization,
 'crash injection matrix covers durable and filesystem boundaries': all(x in matrix for x in ['afterJournalIntentSync','afterStagedArtifactWrite','afterPreviousArtifactPreserve','afterActiveArtifactRename','afterPointerRename','afterJournalCompletionSync']),
 'production crash injection disabled': 'static var productionInjectionEnabled: Bool { false }' in matrix,
 'no recovery mutation executor introduced': all(x not in preflight + auth + authorization for x in ['renameat(', 'unlinkat(', 'launchctl', 'bootstrap(', 'bootout(']),
}
for label, ok in checks.items(): print(('PASS' if ok else 'FAIL') + ': ' + label)
if not all(checks.values()): raise SystemExit(1)
print(f'R15 security audit: {len(checks)}/{len(checks)} passed')
