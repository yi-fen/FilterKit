# P2-18 Change Log

## Darwin SDK compatibility preflight

P2-18 adds a reproducible Apple-SDK compile gate for the Darwin-only peer-authentication APIs introduced in P2-16/P2-17.

### Changes

1. Added `Build/DarwinSDK/FilterKitDarwinSDKProbe.swift` to typecheck the Swift importer surface for `libproc`, `proc_bsdinfo`, `pbi_pidversion`, `proc_pidinfo`, `PROC_PIDTBSDINFO`, and the `getsockopt` call used to retrieve the local peer token.
2. Added `Build/scripts/p218_darwin_sdk_preflight.sh` to run the probe against a selected Apple SDK and, when XcodeGen is installed, generate and build the `FilterKitHelper` target without code signing.
3. Added `Build/scripts/p218_static_gate_audit.py` to enforce source/project wiring and safety invariants on non-Apple hosts.
4. Added `Build/P2-18-DARWIN-SDK-COMPATIBILITY-PREFLIGHT.md` with exact macOS execution instructions and verification boundaries.

### Verification status

- Static audit: 10/10 passed.
- Full Swift syntax parse: recorded in delivery test report.
- Apple SDK typecheck/build: not run; this Linux host has no `xcrun` or Xcode.
- RootHide device runtime and process-inspection permission: not tested.

No production write/activation gate was enabled.
