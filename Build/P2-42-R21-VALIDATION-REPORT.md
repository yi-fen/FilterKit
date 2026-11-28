# P2-42-R21 Validation Report

## Baseline

- Source baseline: `FilterKit-P2-42-R20-Source.zip`
- Verified SHA-256: `1352f860747cc77ac37b47e3b5118945deeddc2df74919bf80572ce4f3dc2fe6`
- `unzip -t` passed before extraction.
- R21 was developed in a fresh work directory.

## Executed checks

- Swift frontend syntax parse: all 244 Swift files under `Sources`, `HelperRuntime`, `App`, and `Tests` passed.
- `Project.yml` YAML parse passed.
- Targeted Swift typecheck passed for the real transaction record, canonical Bundle ID key, and durable store, with minimal stubs for unrelated command/plan/policy dependencies.
- Durable-ledger executable smoke test passed for:
  - atomic insert and reload;
  - persisted `.executing` becoming `.outcomeUnknown` after simulated Helper restart;
  - case-insensitive Bundle ID lookup;
  - explicit `.outcomeUnknown` to `.committed` terminal resolution.
- The smoke harness used the real `HelperAppPluginActivationTransactionLedger` model and real store implementation; command/plan and unrelated policy types were minimal stubs.
- Added XCTest source coverage for coordinator transaction query validation and server request allow-list behavior. XCTest was not run.
- Localization files were not changed.

## Not executed

- Full iOS/Xcode or Helper target build: unavailable because this Linux environment has no `xcodebuild`/Xcode toolchain.
- XCTest execution: not run.
- Darwin-specific Helper runtime, RootHide/ElleKit device tests, real root-owned on-device permission/ownership validation, IPC peer-authentication integration, and crash injection against a jailbroken device: not run.

## Release gates

- Helper APP activation Commit execution remains disabled in production.
- App-side APP activation Commit gate remains disabled.
- No real injection, activation/deactivation, association mutation, or uninstall was executed.
