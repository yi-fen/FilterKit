#!/usr/bin/env python3
from pathlib import Path
root = Path(__file__).resolve().parents[2]
source = (root / 'Sources/Environment/Helper/Runtime/HelperInstallerRecoveryPreflight.swift').read_text()
checks = {
    'explicit active paths derive from canonical release constants': 'HelperRootReleaseSet.executablePath' in source and 'HelperRootReleaseSet.manifestPath' in source and 'HelperRootReleaseSet.launchDaemonPath' in source,
    'staged and previous roots are caller supplied': 'stagedRootRelativePath: String, previousRootRelativePath: String?' in source,
    'stage and previous roots constrained to recovery subtree': 'Library/FilterKit/Helper/Recovery/' in source,
    'path traversal blocked by safe relative path validation': 'HelperPolicy.isSafeRelativePath(value)' in source,
    'overlapping stage and previous roots rejected': 'LayoutError.overlappingRoots' in source,
    'durable journal is reloaded by transaction id': 'journalStore.load(transactionID: transactionID)' in source,
    'filesystem inventory is freshly re-observed': 'reconciliationBackend.observe(activePaths:' in source,
    'launchd label pinned': 'cn.yfen.filterkit.helper' in source,
    'observer code identity is pinned by caller': 'observerCodeIdentitySHA256 == expectedObserverCodeIdentitySHA256' in source,
    'running process pid and executable hash verified': 'pid > 0' in source and 'executableHash == expectedExecutableSHA256' in source,
    'unknown service state fails closed': 'case .unknown: return false' in source,
    'evidence second pass requires exact equality': 'guard first == second' in source,
    'rollback requires upgrade or repin': 'journal.action == .upgrade || journal.action == .repin' in source,
    'rollback requires rollbackRequired and no pending operation': 'journal.state == .rollbackRequired, journal.pendingOperation == nil' in source,
    'rollback requires complete previous hashes': 'Self.hashes(previousArtifacts) == previousExpectedHashes' in source,
    'rollback requires service stopped': 'service.state == .stopped' in source,
    'post-recovery requires exact active hashes': 'Self.hashes(observation.activeArtifacts) == expectedHashes' in source,
    'post-recovery requires pointer match and identity': 'observation.activePointerMatchesObservedArtifacts' in source and 'activeReleasePointer?.releaseIdentifier == expectedReleaseIdentifier' in source,
    'post-recovery requires ownership and stopped service': 'observation.ownershipVerified' in source and 'service.state == .stopped' in source,
    'preflight exposes no filesystem mutation or launchctl': all(token not in source for token in ['renameat(', 'unlinkat(', 'launchctl', 'bootstrap(', 'bootout(']),
}
for label, ok in checks.items():
    print(('PASS' if ok else 'FAIL') + ': ' + label)
if not all(checks.values()):
    raise SystemExit(1)
print(f'R14 static audit: {len(checks)}/{len(checks)} passed')
