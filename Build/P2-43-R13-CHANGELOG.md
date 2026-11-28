# P2-43-R13 Change Log

## Scope
R13 adds a decision-only recovery coordinator and a narrowly scoped atomic writer for the non-authoritative active-release pointer. It does not enable automatic recovery or production installation.

## Added
- `HelperInstallerRecoveryCoordinator`: combines the existing durable journal, verified release identity, and R12 descriptor-observed active/staged/previous inventories. It classifies each inventory as absent, complete, partial, or unexpected.
- Explicit fail-closed handling for partial/mismatched active, staged, and previous inventories; active pointer mismatch; journal/release identity mismatch; upgrade/repin without a complete previous release; and committed-journal/disk disagreement.
- A consistent assessment is explicitly `evidenceConsistentButExecutionNotAuthorized`. A separate executor must reacquire the acceptance lock and re-observe all facts before any side effect.
- `HelperInstallerActiveReleasePointerWriter`: writes only the JSON hint, requires a verified release hash map equal to the caller's independently observed active hashes, uses descriptor-relative no-follow traversal, a root-owned private exclusive temporary file, file fsync, atomic rename, and parent-directory fsync.
- Host smoke matrix covering the nine requested crash/reconciliation cases, an upgrade-with-previous-active case, and pointer writer checks.

## Safety boundary
- Pointer remains a hint, not authority or signature verification.
- Pointer writer is not wired into production recovery/activation.
- No service start/stop, rollback, artifact replacement, provisioning mutation, or launchd operation is implemented.
- The caller contract requires holding the shared installer acceptance lock and freshly observing active hashes before invoking the pointer writer. Production caller integration is intentionally absent.
- No production staging/previous layout is inferred; R12's trusted caller-supplied relative paths remain the boundary.
