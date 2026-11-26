# P2-18 — Darwin SDK Compatibility Preflight

## Goal

Prepare a reproducible macOS/Xcode gate for the Darwin-only APIs used by P2-16/P2-17. This phase does **not** claim an Apple SDK build: the development host for this delivery is Linux and has no `xcrun`, iOS SDK, or Xcode toolchain.

## Added artifacts

- `Build/DarwinSDK/FilterKitDarwinSDKProbe.swift`: compile-only Swift importer probe for `libproc`, `proc_bsdinfo`, `pbi_pidversion`, `proc_pidinfo(PROC_PIDTBSDINFO)`, and `getsockopt(LOCAL_PEERTOKEN)`.
- `Build/scripts/p218_darwin_sdk_preflight.sh`: runs the probe against an installed Apple SDK; if XcodeGen is available, generates the project and builds the `FilterKitHelper` target with signing disabled.
- `Build/scripts/p218_static_gate_audit.py`: host-independent source/configuration guardrails.

## Running on macOS

```sh
Build/scripts/p218_darwin_sdk_preflight.sh iphoneos arm64-apple-ios15.0
```

For a simulator importer check (not a substitute for device build):

```sh
Build/scripts/p218_darwin_sdk_preflight.sh iphonesimulator arm64-apple-ios15.0-simulator
```

## Current verification

- Linux Swift parser checks and source-level audit can be run on this host.
- Apple SDK typecheck/build is **BLOCKED / NOT RUN** because `xcrun` and Xcode are absent.
- No RootHide device, jailbreak bootstrap, or runtime permission test was available.

The probe intentionally tests SDK importability, not runtime authorization. `proc_pidinfo` may still fail for a peer process under the actual iOS/RootHide privilege model; production code must continue to fail closed in that case.

## Safety

All production deployment and plugin-association execution release flags remain `false`. No write path is enabled by P2-18.
