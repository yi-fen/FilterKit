# P1-21 Test Report

## Passed checks

- Full Swift syntax parse for `App`, `Sources`, `Tests`, and `HelperRuntime`: PASS.
- Helper runtime source subset Foundation typecheck on Linux Swift 6.2.1: PASS.
- Separate `FilterKitHelper` executable source set compiled and linked on Linux: PASS.
- Linux helper executable startup without libroot exited non-zero with `jailbreakRootUnavailable`: PASS (expected fail-closed behavior; not a Darwin/iOS runtime test).
- Root-owned `0600` manifest read smoke: PASS.
- Manifest symbolic-link leaf rejection smoke: PASS.
- Persistent JSONL audit append smoke: PASS.
- Audit rotation smoke (`audit.jsonl` plus retained generation): PASS.
- Lifecycle plan fixed paths, root-installer-only, manifest mode `0600`: PASS.
- Project YAML parsed; targets are `FilterKit`, `FilterKitHelper`, `FilterKitTests`: PASS.
- Project identity/signing static verification: PASS.
- Architecture structure verification: PASS.
- Localization parity: 225 matching keys in English and Simplified Chinese, no duplicate keys: PASS.
- ZIP integrity: PASS.

## Not run / not claimed

- XcodeGen project generation: NOT RUN (XcodeGen unavailable).
- Xcode/iOS SDK build or link of `FilterKitHelper`: NOT RUN.
- Darwin compile/runtime of `getpeereid`, `LOCAL_PEERPID`, private `csops`, `openat` and `O_NOFOLLOW`: NOT RUN on an Apple SDK/device.
- XCTest execution: NOT RUN.
- launchd bootstrap/bootout or package install/uninstall: NOT RUN.
- RootHide and Rootless device validation: NOT RUN.
- Helper CDHash pinning on device: NOT RUN.
- Actual root writes to TweakInject: NOT implemented and NOT performed.

## Safety assertions

- `HelperDeploymentCoordinator.executionReleased` remains `false`.
- The launchd plist template remains disabled (`Disabled=true`, `RunAtLoad=false`, `KeepAlive=false`).
- Runtime only answers health checks; every operation request is rejected, even if a manifest were to set `executionEnabled=true`.
- No helper installer or App-triggered lifecycle mutation was added.
- No dpkg database, plugin directory, target App Bundle, or jailbreak injection configuration was modified.
