# P2-43-R9 Change Log

## Scope

R9 adds a closed trusted-installer coordination boundary over the R7 signed Provisioning envelope, R8 Trusted Provisioning Store, exact release artifact verification, durable transaction journal model, and the existing Helper/startup acceptance lock.

## Source changes

- Added `HelperTrustedInstallerCoordinator` and immutable `HelperPreparedRootInstall`.
- `prepare` verifies the signed Provisioning envelope through the configured signing-key verifier, binds the Provisioning JBROOT to the closed transaction plan, verifies the exact three-artifact release set, and creates a validated initial transaction journal. It performs no filesystem, Keychain, launchd, or Helper mutation.
- Added the `HelperRootInstallerExecuting` adapter contract. The default `HelperUnavailableRootInstaller` is deliberately not production-ready.
- The adapter contract requires a durable journal around every transaction step and a Provisioning commit callback only after release activation/verification. A rejected Provisioning commit permits rollback; an indeterminate commit requires leaving the new release activated but stopped and recording manual intervention.
- The coordinator reconciles R8 pending/checkpoint state after a commit I/O error before classifying it as rejected or indeterminate.
- The only execution entry point checks the existing execution gate, requires both a production-ready adapter and Trusted Provisioning Store, then acquires the same persistent lock inode used by Helper startup acceptance.
- Changed `HelperReleaseAcceptanceLock` to wait for an exclusive flock (retrying `EINTR`) rather than failing immediately on ordinary lock contention.
- Strengthened `HelperRootReleaseSet` to decode the current `HelperDeploymentManifest` schema and verify App Bundle ID, Team ID, App CDHash, Helper CDHash, UID/GID, install paths, and disabled execution state against signed Provisioning.
- Added coordinator unit-test source and R9 static audit.

## Safety state

- No production Root Installer adapter is implemented.
- Generated install/upgrade/repin plans still set `executionEnabled = false`.
- `HelperUnavailableRootInstaller` is the default.
- No production install, upgrade, Repin, launchd, or Provisioning write is enabled by R9.
