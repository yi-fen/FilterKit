# P1-23 Test Report

## Passed

- Full project Swift parser check.
- Helper execution, ownership verifier, Mach-O parser, and journal/recovery subset typecheck on Linux.
- P1-22 paired deployment smoke rerun after journal integration.
- Root-owned manifest verifier smoke using a synthetic arm64 Mach-O with LC_UUID.
- Exact dylib/plist SHA-256 verification and Mach-O identity fingerprint verification.
- Explicit package-owned and unavailable ownership evidence are denied; only verified-unowned evidence is accepted.
- Tampered deployed dylib rejected by payload hash check.
- Root-owned journal create/load/update/clear smoke.
- Recovery planner rollback plan after dylib commit.
- Recovery planner committed cleanup plan.
- Foreign transaction cannot replace the active journal.
- Project.yml YAML parse and configured target checks.
- Architecture verifier.
- Localization parity verifier.
- ZIP integrity.

## Not run / not claimed

- XcodeGen generation, Xcode/iOS SDK build, XCTest execution.
- Darwin/iOS compile of POSIX filesystem operations.
- RootHide / Rootless device verification.
- Actual root Helper startup or launchd integration.
- Startup recovery action execution; P1-23 recovery planner is pure and not connected to mutation dispatch.
- First-install / backup-restore root authorization.
- Helper IPC operation dispatch or actual TweakInject writes.

## Release gates retained

- `HelperDeploymentCoordinator.executionReleased == false`.
- Helper runtime rejects all operation requests.
- `HelperDeploymentManifest.disabledTemplate(...).executionEnabled == false`.
- Removal remains unavailable.
