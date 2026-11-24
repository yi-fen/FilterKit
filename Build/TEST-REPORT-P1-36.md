# Test Report — P1-36

## Passed in this environment

- Swift syntax parse across all `Sources`, `App`, `HelperRuntime` and `Tests/UnitTests` files.
- Focused Linux Swift typecheck for the P1-36 durable store and recovery assessment with installer model dependencies.
- P1-36 executable smoke test:
  - root-owned `0700` journal directory accepted;
  - journal saved and loaded with exact Codable equality;
  - file fsync + atomic rename + directory fsync path completed;
  - temporary file absent after successful save;
  - non-`0700` directory rejected;
  - recovery assessment validates the journal chain before recommendation;
  - corrupted chain rejected.
- Project identity/signing configuration check passed.
- Architecture structure check passed (8 required files).
- Localization parity passed: 237 matching zh-Hans/en keys.

## Added but not executed

- `Tests/UnitTests/HelperInstallerDurableStoreTests.swift` adds XCTest coverage for durable round-trip, unsafe directory rejection and corrupted journal rejection. XCTest was not run because Xcode/iOS SDK is not available in this environment.

## Not run / not claimed

- XcodeGen, Xcode/iOS SDK build, XCTest or Darwin compilation.
- Actual jailbreak root ownership/mode behavior on Dopamine RootHide/Rootless.
- Multi-process contention, power-loss testing, reboot recovery or anti-rollback protection.
- Privileged installer execution, multi-file activation/rollback, launchd bootstrap/bootout or socket lifecycle.
- Code-signature, CDHash or signed release provenance verification.

## Release gates retained

- `executionEnabled=false` for every current installer plan.
- No production Root Installer adapter or privilege escalation path.
- Helper deployment/recovery mutation remains disabled.
- launchd remains disabled and is not invoked.
