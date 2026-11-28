#!/usr/bin/env python3
from pathlib import Path
root = Path(__file__).resolve().parents[2]
coordinator = (root / 'Sources/Environment/Helper/Runtime/HelperInstallerRecoveryCoordinator.swift').read_text()
writer = (root / 'Sources/Environment/Helper/Runtime/HelperInstallerActiveReleasePointerWriter.swift').read_text()
checks = {
    'coordinator validates journal chain': 'journal.validateChain()' in coordinator,
    'coordinator binds journal release identifier': 'verifiedRelease.releaseIdentifier == journal.releaseIdentifier' in coordinator,
    'coordinator binds generation': 'verifiedRelease.generation == journal.generation' in coordinator,
    'coordinator requires ownership evidence': 'observation.ownershipVerified' in coordinator,
    'partial inventory fails closed': 'active == .partial || active == .unexpected || staged == .partial' in coordinator,
    'upgrade requires previous release': 'previous == .complete' in coordinator,
    'committed state checks pointer': 'observation.activePointerMatchesObservedArtifacts' in coordinator,
    'coordinator never invokes launchctl': 'launchctl' not in coordinator,
    'coordinator has no filesystem mutation': all(token not in coordinator for token in ['unlinkat(', 'renameat(', 'openat(']),
    'consistent evidence does not authorize execution': 'evidenceConsistentButExecutionNotAuthorized' in coordinator,
    'writer requires exact verified hashes': 'release.hashes == observedActiveHashes' in writer,
    'writer uses no-follow directory traversal': 'O_NOFOLLOW' in writer,
    'writer creates exclusive private temporary file': 'O_CREAT | O_EXCL | O_NOFOLLOW' in writer and '0o600' in writer,
    'writer fsyncs file and directory': 'fsync(fd)' in writer and 'fsync(parentFD)' in writer,
    'writer atomically renames pointer': 'renameat(parentFD, temp, parentFD, destination)' in writer,
    'writer rejects unsafe existing pointer': 'WriterError.unsafeExistingPointer' in writer,
    'writer not wired into production coordinator': 'HelperInstallerActiveReleasePointerWriter' not in coordinator,
}
for label, ok in checks.items():
    print(('PASS' if ok else 'FAIL') + ': ' + label)
if not all(checks.values()):
    raise SystemExit(1)
print(f'R13 static audit: {len(checks)}/{len(checks)} passed')
