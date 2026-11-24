# Test Report — P1-30

## Passed

- Full project Swift syntax parse.
- Helper + Runtime + all Execution sources Linux Swift typecheck.
- P1-30 isolated POSIX transaction smoke running as root in a temporary directory.
- First-install deployment of dylib + plist + Schema 3 manifest.
- Update deployment replacing all three files in one journaled transaction.
- Stale previous-file hash rejection before mutation.
- Exact payload and manifest SHA-256 verification.
- Schema 3 manifest Plugin UUID, file-name, payload-hash and association-field validation.
- Root-owned manifest mode `0600` validation.
- Update rejects stale previous-file hashes before mutation.
- Simulated process-loss recovery after `prepared`, `backingUp`, `installingDylib`, `installingPlist`, and `installingManifest`.
- First-install partial deployment rollback removes all three newly created files.
- Committed-phase recovery keeps all new files and removes verified backups.
- Read-only pending-journal probe detects interrupted transaction.
- Recovery idempotence after rollback and after committed cleanup.
- P1-28 pipeline smoke regression.
- P1-29 production backend preflight smoke regression; production mutation gate remains closed.
- Project configuration check.
- Architecture check.
- Localization parity: 225 matching zh-Hans/en keys.

## Not run / not claimed

- XcodeGen generation or Xcode/iOS SDK build.
- XCTest execution.
- Darwin compilation or iOS code-signing/CDHash validation.
- launchd Helper installation/bootstrap.
- RootHide/Rootless on-device validation.
- Actual TweakInject writes.
- Real device power-loss testing; Linux process-loss simulation is not a substitute for filesystem/hardware crash testing.

## Release gates retained

- `HelperProductionDeploymentBackend.executionReleased == false`.
- Dispatcher execution release remains false.
- Helper deployment manifest template remains `executionEnabled == false`.
- Helper Runtime only performs read-only startup journal inspection and blocks service if recovery is pending; it does not auto-recover by writing.
- Plugin deletion remains unavailable.
