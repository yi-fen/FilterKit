# P2-42-R6 Validation Report

## Baseline

- Source baseline: `FilterKit-P2-42-R5-Source.zip`
- Baseline SHA-256: `8ed2a1c89ac89ff11bdd52cbb6310adcfa45491807655af8dad28f00af2cade7`

## Executed checks

- Swift frontend parse: all 227 Swift files under `Sources` and `Tests` passed.
- Swift typecheck: `InstalledApp.swift`, `PluginAppDisplayIndex.swift`, and `PluginHostProcessProbe.swift` passed on the available Linux Swift toolchain.
- Compiled and executed standalone smoke harness:
  - case-insensitive Bundle ID lookup passed;
  - display-name trimming and executable lookup passed;
  - unmatched Bundle ID fallback passed;
  - deterministic unique-name ordering passed;
  - Linux correctly reports the Darwin-only process probe as unavailable.
- Localization validation: zh-Hans and en each contain 491 unique keys; key sets match exactly.
- Confirmed unknown-source strings are `来源：未知` and `Source: unknown`.
- Confirmed the Plugin page runtime refresh calls only the process probe and does not initiate another plugin scan.

## Not executed / limitations

- `xcodebuild` is unavailable in this Linux environment. No iOS Simulator/device build or XCTest run is claimed.
- Darwin/iOS `libproc` process enumeration was not compiled against an Apple SDK or exercised on a RootHide device. Device validation is still required, including process visibility and exact executable-path behavior under the target iOS/rootless jailbreak environment.
- R6 detects a visible host-app process only. It does not prove that the target plugin dylib is loaded in that process. A trusted remote loaded-image attestation capability remains future work.
- No injection, toggle, uninstall, backup restore write, association mutation, or jailbreak filesystem write was performed.

## Result

Offline source checks and the standalone app-name/runtime-probe smoke test passed. iOS build, XCTest, and RootHide/ElleKit device acceptance remain pending. Production mutation gates remain closed.
