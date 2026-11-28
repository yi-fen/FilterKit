# P2-42-R18 Validation Report

## Baseline integrity

- Baseline archive: `FilterKit-P2-42-R17-Source.zip`
- Baseline SHA-256 verified: `85cee52742183f1246fe2859740b092e59ef3ff03fcd32feb326786e0ebc35b3`
- Baseline ZIP integrity: passed (`unzip -t`).
- Work was performed in a fresh R18 directory; the R17 archive and R17 worktree were not modified.

## Executed checks

- Swift frontend parse: all 235 Swift files under `Sources` and `Tests` passed.
- `Project.yml` YAML parse: passed.
- Targeted Swift compile-and-run smoke harnesses compiled the actual changed source files with minimal platform/domain stubs:
  - Association plan and editor: 7 assertions passed (case-variant duplicate detection, Fixed Owner collision, canonical installed-App lookup, canonical add/remove, and default-disabled additions).
  - APP activation resolver: 2 assertions passed (case-insensitive Fixed Owner and Filter.plist matching).
  - Read-only association inventory: 5 assertions passed (case-insensitive installed-App join, preservation of manifest Fixed Owner spelling, installed App spelling in the effective projection, case-insensitive availability, and duplicate fail-closed behavior).
- No localization strings changed.

## Not executed / environment limits

- Full iOS app/Helper build and XCTest execution were not run because `xcodebuild` is unavailable in this Linux environment. Added XCTest source is parse-checked but not reported as executed.
- The smoke harnesses are targeted compile-and-run checks with minimal stubs for unrelated platform/domain types. They are not substitutes for full Xcode target compilation or XCTest.
- Signed IPC, Helper filesystem transactions, timeout/restart recovery, RootHide/ElleKit behavior, and jailbreak-device lifecycle tests were not exercised.

## Safety state

All production mutation gates remain closed. No device files were modified. No real injection, per-App activation, association commit, or uninstall was performed.
