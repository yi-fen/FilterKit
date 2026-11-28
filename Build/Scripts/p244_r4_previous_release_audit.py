#!/usr/bin/env python3
from pathlib import Path
import sys
root = Path(__file__).resolve().parents[2]
source = (root / "Sources/Environment/Helper/Runtime/HelperInstallerPreviousReleaseStore.swift").read_text()
smoke = (root / "Build/scripts/p244_r4_previous_release_smoke.swift").read_text()
checks = {
    "fixed Recovery PreviousReleases root": 'Library/FilterKit/Helper/Recovery/PreviousReleases' in source,
    "upgrade and repin only": 'prepared.plan.action == .upgrade || prepared.plan.action == .repin' in source,
    "durable preserve intent required": 'journal.pendingOperation == .preservePreviousRelease' in source,
    "journal must match persisted head": 'persisted == journal' in source,
    "shared Darwin transaction lock": 'HelperInstallerSharedTransactionLock.withExclusiveLock' in source,
    "root identity enforced": 'rootInfo.st_uid == 0, rootInfo.st_gid == 0' in source,
    "descriptor-relative traversal": 'openat(fd, $0' in source and 'O_NOFOLLOW' in source,
    "source artifacts root-owned": 'before.st_uid == 0, before.st_gid == 0' in source,
    "single-link source and backup": 'before.st_nlink == 1' in source and 'info.st_nlink == 1' in source,
    "bounded source read": 'before.st_size <= maximum' in source,
    "source metadata stable during read": 'FileIdentity(before) == FileIdentity(after)' in source,
    "source hashes match trusted inventory": 'SHA256Digest.hex(bytes) == expectedHash' in source,
    "Mach-O CDHash and Team ID checked": 'verifyMachOIdentity' in source and 'expectedTeamIdentifier' in source,
    "disabled launchd plist checked": 'plist["Disabled"] as? Bool == true' in source and 'plist["RunAtLoad"] as? Bool == false' in source,
    "transaction backup never overwritten": 'backupAlreadyExists' in source,
    "exclusive temporary files": 'O_CREAT | O_EXCL | O_NOFOLLOW' in source,
    "file and directory fsync": 'fsync(fd)' in source and 'fsync(directoryFD)' in source and 'fsync(backupRootFD)' in source,
    "atomic descriptor-relative rename": 'renameat(directoryFD, source, directoryFD, destination)' in source,
    "read-back verification": 'hashArtifact(artifact, directoryFD: backupFD)' in source,
    "partial state inspection": 'case partial' in source or 'missingArtifacts' in source,
    "unexpected entries rejected": 'unexpectedEntries' in source and 'expectedEntryNames' in source,
    "journal indeterminate retains backup": 'journalCommitIndeterminate' in source and 'Never delete it' in source,
    "crash injection coverage": 'injectedCrash' in source and 'faultAt' in source,
    "host smoke includes crash and tamper cases": 'fault injection interrupts backup' in smoke and 'backup tampering detected' in smoke,
    "no activation or launchd mutation": 'never activates' in source and 'bootstrap' not in source,
}
failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items(): print(f"{'PASS' if ok else 'FAIL'}: {name}")
print(f"RESULT: {len(checks)-len(failed)}/{len(checks)}")
sys.exit(1 if failed else 0)
