# P2-44-R8 — Staged / Previous Disk Evidence Host Validation

## Scope

R8 is a validation-focused phase for the R7 disk-evidence loaders. It adds a Host smoke harness that compiles and executes the actual `HelperInstallerStagedReleaseStore.swift` and `HelperInstallerPreviousReleaseStore.swift` implementations against real root-owned filesystem fixtures. It does not add a second store, scanner, installer, or mutation path.

## Added

- `Build/scripts/p244_r8_disk_evidence_smoke.swift`
- `Build/scripts/run_p244_r8_disk_evidence_smoke.sh`
- `Build/scripts/p244_r8_disk_evidence_audit.py`
- `Build/P2-44-R8-CHANGELOG.md`
- `Build/P2-44-R8-VALIDATION-REPORT.md`

## Host test coverage

Both Staged and Previous loaders are exercised against actual filesystem entries for:

- Successful read of the exact three-artifact inventory.
- Missing transaction / backup.
- Incomplete expected-hash map.
- Modified artifact bytes and mismatched expected hashes.
- Missing member of the three-file set.
- Unexpected directory entries.
- Symlink artifact and symlink transaction directory.
- Hard-linked artifact.
- Incorrect artifact mode.
- Group/world-writable transaction directory.
- Non-root-owned artifact.

The test invokes the real loader methods; only surrounding domain types and the activation transaction-lock abstraction are narrow Host shims. This validates descriptor-relative file access and the actual file validation logic, not the complete Helper target or Darwin locking semantics.

## Security posture

- Staged and Previous remain separate, transaction-scoped stores.
- Loaders continue to require the caller to hold the activation lock and do not recursively acquire it.
- R7 activation preflight remains responsible for binding Staged bytes to the verified release and Previous bytes to the expected Active preimage.
- No launchd control, Helper startup, production mutation adapter, or production write gate was enabled.
