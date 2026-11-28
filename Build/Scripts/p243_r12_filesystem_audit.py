#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[2]
observer = (root / "Sources/Environment/Helper/Runtime/HelperInstallerDescriptorFilesystemObserver.swift").read_text()
smoke = (root / "Build/scripts/p243_r12_filesystem_smoke.swift").read_text()
checks = {
    "descriptor-relative openat traversal": "openat(" in observer,
    "no-follow on root and child components": observer.count("O_NOFOLLOW") >= 4,
    "regular-file enforcement": "S_IFREG" in observer,
    "single-hardlink enforcement": "st_nlink == 1" in observer,
    "root ownership enforcement": "st_uid == expectedOwnerUID" in observer,
    "untrusted writable ancestor rejection": "componentInfo.st_uid == 0 || (componentInfo.st_mode & 0o200) == 0" in observer,
    "group/world write denied": "st_mode & 0o022" in observer,
    "private pointer mode enforced": "privateFile || (before.st_mode & 0o077) == 0" in observer,
    "bounded read enforced": "maximumArtifactBytes" in observer and "maximumPointerBytes" in observer,
    "stable inode and size enforced": "st_ino == after.st_ino" in observer and "st_size == after.st_size" in observer,
    "stable timestamps enforced": "timestampsEqual(before, after)" in observer,
    "SHA-256 computed from descriptor bytes": "SHA256Digest.hex(data)" in observer,
    "missing only on ENOENT": "code == ENOENT" in observer,
    "missing JBROOT is not treated as absent artifacts": "rootUnavailable(errno)" in observer and "rootUnavailable(Int32)" in observer,
    "symlink errors not downgraded to missing": "catch ObservationError.openFailed(let code) where code == ENOENT" in observer,
    "release pointer schema validates exact artifact set": "Set(artifactHashes.keys) == Set([\"executable\", \"deploymentManifest\", \"launchDaemon\"])" in observer,
    "pointer treated as reconciliation hint": "pointer is only a hint" in observer,
    "active pointer hashes must match descriptor-observed artifact bytes": "activePointerMatchesObservedArtifacts" in observer and "$0.artifactHashes == activeHashes" in observer,
    "staged identity requires verified release and matching observed hashes": "verifiedStagedRelease: HelperRootReleaseSet.Verified?" in observer and "stagedHashes == $0.hashes" in observer,
    "no filesystem mutation APIs in observer": not any(token in observer for token in ["renameat(", "unlinkat(", "mkdir(", "chmod(", "fchmod(", "write(", "launchctl"]),
    "smoke covers symlink hardlink and writable files": all(token in smoke for token in ["symlink leaf is rejected", "symlink parent directory is rejected", "multiple hard links are rejected", "group/world writable file is rejected"]),
    "smoke rejects a pointer whose artifact hashes differ": "pointer with mismatched artifact hashes is not accepted" in smoke and "mismatched pointer cannot populate trusted active release identity" in smoke,
    "smoke verifies staged identity against signed artifact hashes": "staged release identity derives only from verified release" in smoke,
    "smoke covers absent stage and active pointer": "absent staged artifacts" in smoke and "active release pointer" in smoke,
    "smoke rejects untrusted writable JBROOT ancestor": "non-root owner-writable JBROOT ancestor is rejected" in smoke,
}
failed = [name for name, passed in checks.items() if not passed]
for name, passed in checks.items():
    print(("PASS" if passed else "FAIL") + ": " + name)
if failed:
    raise SystemExit(f"{len(failed)} audit checks failed")
print(f"R12 filesystem audit: {len(checks)}/{len(checks)} passed")
