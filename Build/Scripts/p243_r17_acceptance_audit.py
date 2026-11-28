#!/usr/bin/env python3
from pathlib import Path
root = Path(__file__).resolve().parents[2]
runner = (root / 'Sources/Environment/Helper/Runtime/HelperInstallerRecoveryAcceptanceRunner.swift').read_text()
preflight = (root / 'Sources/Environment/Helper/Runtime/HelperInstallerRecoveryPreflight.swift').read_text()
auth = (root / 'Sources/Environment/Helper/Runtime/HelperInstallerRecoveryAuthorization.swift').read_text()
tests = (root / 'Tests/UnitTests/HelperInstallerRecoveryAcceptanceRunnerTests.swift').read_text()
checks = {
    'runner calls the real double-inspection preflight': 'inspectTwiceUnderSharedLock(' in runner and 'inspectTwiceUnderSharedLock' in preflight,
    'preflight holds the shared transaction lock': 'HelperInstallerSharedTransactionLock.withExclusiveLock' in preflight,
    'report contains all three inventories': all(x in runner for x in ['let active: [ArtifactEvidence]', 'let staged: [ArtifactEvidence]', 'let previous: [ArtifactEvidence]']),
    'report captures inode and ownership metadata': all(x in runner for x in ['ownerUID', 'groupID', 'device', 'inode', 'mode']),
    'report captures pointer and service evidence': all(x in runner for x in ['pointerMatchesObservedArtifacts', 'serviceObserverCodeIdentitySHA256', 'serviceState']),
    'digest is deterministic over sorted artifact inventories': 'records.keys.sorted' in runner and 'lines.joined(separator: "\\n")' in runner,
    'execution authorization is hard-coded false in reports': 'executionAuthorized: false' in runner,
    'human review only delegates to review approval': 'approveForReview(' in runner and 'approveForReview(' in auth,
    'execution remains denied by authorization type': 'throw AuthorizationError.executionNotAvailable' in auth,
    'no mutation or launchd control primitive added': not any(x in runner for x in ['openat(', 'renameat(', 'unlinkat(', 'launchctl', 'posix_spawn', 'chmod(', 'chown(']),
    'service adapter authentication boundary documented': 'OS-authenticated IPC peer' in runner,
    'runner directly delegates report validation to R15 authenticated observer': 'HelperInstallerAuthenticatedServiceObserver.validate(' in runner and 'validateAuthenticatedServiceReport(' in runner,
    'report JSON round-trip test exists': 'testAcceptanceReportRoundTripsAsSortedJSON' in tests,
    'report remains non-authorizing in tests': 'XCTAssertFalse(decoded.executionAuthorized)' in tests,
}
for label, ok in checks.items():
    print(('PASS' if ok else 'FAIL') + ': ' + label)
if not all(checks.values()):
    raise SystemExit(1)
print(f'SUMMARY: {len(checks)}/{len(checks)} passed')
