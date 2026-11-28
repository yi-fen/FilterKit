# P2-42-R3 — Helper Three-File Uninstall Transaction

## Scope

Implement the Helper-side transaction primitive for uninstalling a FilterKit-owned plugin. This stage deliberately does not connect the primitive to production IPC or enable destructive operations.

## Changes

- Added `HelperThreeFileUninstallTransaction`.
- Requires a Helper-created `HelperOwnershipProof` with verified binary identity and exact dylib, plist, and manifest SHA-256 values.
- Requires an explicit set of enabled App Bundle IDs from a fresh Helper-side activation snapshot and refuses removal unless the set is empty. The snapshot provider and IPC caller are intentionally not wired in this phase.
- Re-hashes all three root-owned regular files immediately before removal; rejects missing, changed, symlinked, multiply-linked, non-root-owned, or unsafe-mode files.
- Moves the three files into transaction-specific quarantine names under a durable journal.
- Pre-commit recovery restores the exact three original files; post-commit recovery completes deletion of quarantined files.
- Recovery is transaction-ID-bound and leaves the journal in place when file state cannot be proven safe.
- Startup recovery inspection now detects a pending uninstall journal and blocks normal operation; overlapping uninstall and deployment journals are treated as invalid recovery state.
- Added unit tests for successful removal, pre-commit rollback, post-commit completion, and hash mismatch rejection.

## Explicitly not changed

- No Helper IPC operation was added or enabled for uninstall.
- No Plugin UI action was connected to filesystem deletion.
- No release/execution gate was opened.
- No ownership proof, package-manager policy, peer authentication, or existing three-file install/update transaction was weakened.
