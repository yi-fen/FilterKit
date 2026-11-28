# P2-43-R15 Changelog

## Scope
R15 hardens the recovery review boundary. It does not enable production install, activation, recovery, rollback, or launchd control.

## Changes

- Added `HelperInstallerSharedTransactionLock`, delegating recovery inspection to the existing `HelperReleaseAcceptanceLock` and therefore the same persistent `.filterkit-root-activation.lock` inode used by `HelperRootAtomicActivationExecutor`.
- Added `inspectTwiceUnderSharedLock` to `HelperInstallerRecoveryPreflight`. It reloads the durable journal and filesystem evidence twice while holding the shared exclusive lock, obtains a fresh service observation for each pass, and rejects any evidence drift.
- Added `HelperInstallerAuthenticatedServiceObserver`. It validates a one-use challenge, the OS-authenticated IPC peer identity (including kernel audit-token digest), pinned CDHash, signing identifier, Team ID, and observer code-identity SHA-256 before accepting a service observation.
- Added `HelperInstallerRecoveryAuthorization`. It supports evidence-only and review-approved states but deliberately rejects execution authorization.
- Added `HelperInstallerCrashInjectionMatrix`, a deterministic catalogue of transaction crash boundaries and required post-crash dispositions. Production injection remains disabled.
- Added R15 host smoke and static audit scripts.

## Explicit limitations

- No new Darwin launchd state collector is implemented. The authenticated observer validates evidence returned through the existing authenticated IPC transport; a platform adapter must still obtain authoritative launchd state and the live executable hash.
- The shared lock is effective only for participants that use the same JBROOT and persistent lock inode. Any future executor must hold it for the complete evidence-to-side-effect interval and must not unlink/replace the lock file.
- R15 does not add a recovery executor, rollback executor, launchd mutation, or artifact mutation.
- Crash injection is a test matrix/catalogue, not real power-loss or kernel-crash injection.
