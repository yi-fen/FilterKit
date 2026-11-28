# P2-42-R17 Validation Report

## Baseline integrity

- Baseline archive: `FilterKit-P2-42-R16-Source.zip`
- Baseline SHA-256 verified: `d685f0496d9b8440fba33852c145e8007f2f3b36e53d8c46249d60f6fdcc06b9`
- Baseline ZIP integrity: passed (`unzip -t`).

## Executed checks

- Swift frontend parse: all 235 Swift files under `Sources` and `Tests` passed.
- Targeted Swift compile-and-run smoke harness: 11 assertions passed. Covered mixed-case Fixed Owner lookup, mixed-case Additional App Association lookup, case-variant duplicate fail-closed behavior, topology duplicate detection, default-disabled new association, mixed-case Filter.plist target matching/removal, and duplicate Bundle target rejection.
- `Project.yml` YAML parse: passed.
- Localization: `en.lproj` and `zh-Hans.lproj` each contain 510 unique keys; key sets are identical.
- No localization changes were required.

## Not executed / environment limits

- Full iOS app build and XCTest execution were not run because `xcodebuild` is unavailable in this Linux environment.
- The targeted smoke harness compiles the shared canonicalizer, manifest/read-state model, binding topology, ElleKit Filter strategy, and Helper association planner together. It is not a substitute for the complete Xcode app/Helper target build.
- Helper filesystem transactions, signed IPC, RootHide/ElleKit device behavior, and jailbreak-device integration were not exercised.

## Safety state

All production mutation gates remain closed. No device files were modified. No real injection, per-App activation, association commit, or uninstall was performed.
