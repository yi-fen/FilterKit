# Test Report — P1-35

## Passed in this environment

- Full Swift syntax parse across `Sources`, `App`, `HelperRuntime`, and `Tests/UnitTests`.
- Focused Linux Swift typecheck of the new release verifier, transaction journal and execution gate with their model dependencies.
- P1-35 executable/launchd artifact smoke test: exact SHA-256 inventory matches staged bytes.
- Fixed launchd Label and ProgramArguments validation.
- `Disabled=true`, `RunAtLoad=false`, `KeepAlive=false` enforced by release verifier.
- Altered executable bytes rejected.
- Upgrade journal ordering: verify → preserve previous release → stage → activate → rollback → rolled back.
- Out-of-order activation rejected.
- Journal hash-chain replay validation implemented.
- Execution gate rejects the plan with `planNotReleased` even when all evidence booleans are true.
- Project configuration verification passed.
- Architecture structure verification passed (8 required files).
- Localization parity passed: 237 matching zh-Hans/en keys.

## Added but not executed

- `Tests/UnitTests/HelperInstallerTransactionTests.swift` includes XCTest coverage for artifact integrity, journal transitions, tamper detection and execution gating. XCTest was not run because this environment does not provide Xcode/iOS SDK.

## Not run / not claimed

- XcodeGen, Xcode/iOS SDK build, XCTest execution or Darwin compilation.
- Real code-signing, Mach-O signature validation, App/Helper CDHash extraction or signed release provenance verification.
- Privileged Root Installer execution, durable journal writes, fsync, atomic file activation or crash recovery.
- launchd bootstrap/bootout, socket directory lifecycle or Root-owned manifest installation.
- RootHide/Rootless device testing, actual TweakInject deployment/recovery, target App modification or re-signing.

## Release gates retained

- `HelperInstallerTransactionPlan.executionEnabled` remains false.
- `HelperInstallerExecutionGate` rejects all current plans.
- App cannot install Helper or grant itself root.
- Helper plugin deployment/recovery mutation remains disabled.
- launchd remains disabled and is not invoked.
