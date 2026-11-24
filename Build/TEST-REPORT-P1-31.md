# Test Report — P1-31

## Passed

- Full project Swift syntax parse.
- Helper + Runtime + Execution sources Linux Swift typecheck.
- P1-30 three-file transaction regression smoke.
- P1-31 startup recovery classification (clean / pending three-file journal).
- Explicit root-only three-file recovery coordinator smoke.
- Recovery coordinator returns clean after successful recovery.
- Symlink substitution at a transaction destination is rejected; external symlink target remains unchanged.
- Group/world-writable deployed file is rejected during recovery.
- Unsafe recovery preserves the pending journal for manual intervention.
- Existing first-install, update, simulated pre-commit crash phases, committed cleanup, and idempotence checks.
- Project configuration check.
- Architecture check.
- Localization parity: 225 matching zh-Hans/en keys.
- ZIP integrity.

## Darwin compatibility status

- Reviewed source use of `openat`, `fstatat`, `renameat`, `unlinkat`, `O_NOFOLLOW`, `O_DIRECTORY`, `O_CLOEXEC`, `AT_SYMLINK_NOFOLLOW`, `fchown`, `fchmod`, `fsync`, and `geteuid` under conditional Darwin/Glibc imports.
- This is a source/API review only. No Darwin compiler or iOS SDK is available in this environment.

## Not run / not claimed

- XcodeGen generation or Xcode/iOS SDK build.
- XCTest execution.
- Darwin compilation or iOS code-signing/CDHash validation.
- launchd Helper installation/bootstrap.
- RootHide/Rootless on-device validation.
- Actual TweakInject writes.
- Real device power-loss testing.

## Release gates retained

- `HelperProductionDeploymentBackend.executionReleased == false`.
- Dispatcher execution release remains false.
- Helper deployment manifest template remains `executionEnabled == false`.
- Runtime startup performs read-only journal inspection and blocks service if recovery is pending.
- Explicit recovery coordinator is not called by Runtime startup.
- Plugin deletion remains unavailable.
