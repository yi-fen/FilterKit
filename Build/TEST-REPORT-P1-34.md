# Test Report — P1-34

## Passed

- Full Swift syntax parse across `Sources`, `App`, `HelperRuntime`, and `Tests`.
- Helper/runtime Linux Swift typecheck (recorded after implementation).
- P1-34 installer provisioning smoke test: complementary exact App/Helper CDHash pins.
- Disabled root manifest retains `executionEnabled=false`.
- Generated launchd plist remains disabled with `RunAtLoad=false` and `KeepAlive=false`.
- Upgrade plan preserves previous release and contains rollback steps.
- Dry-run confirms no writes, no launchd invocation, and no execution release.
- Provisioning path validation rejects paths outside the selected jbroot.
- Project configuration, architecture and localization parity checks.
- ZIP integrity.

## Not run / not claimed

- XcodeGen, Xcode/iOS SDK build, XCTest execution or Darwin compilation.
- Real code-signing, App/Helper CDHash extraction, signed release provenance verification.
- Root installer execution, manifest file installation, launchd bootstrap/bootout.
- AF_UNIX socket directory ownership/mode validation on iOS.
- RootHide/Rootless device testing, actual TweakInject deployment or recovery.

## Release gates retained

- App cannot invoke installer plans or grant itself root.
- Helper deployment and recovery mutation remain disabled.
- Generated launchd job remains disabled.
- No target App Bundle modification or re-signing.
