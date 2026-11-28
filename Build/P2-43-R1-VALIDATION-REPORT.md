# P2-43-R1 Validation Report

## Baseline

- Source baseline: `FilterKit-P2-42-R24-Source.zip`
- Verified baseline SHA-256: `2eaa64898736efd58298fc351c6d78d73b5e9ba0192db5c2c1354092a50b73a0`
- Baseline ZIP integrity: `unzip -t` passed.
- Development used a fresh extraction at `FilterKit-P2-43-R1-Work`; R24 was not modified.

## Executed checks

- Swift frontend syntax parse: all 242 Swift files under `Sources` and `Tests` passed.
- Targeted Swift executable compiled and ran the actual `HelperBundleIdentifierKey.swift` and `BackupBundleIdentity.swift` sources: 7 assertions passed (case-insensitive owner match, mismatch rejection, association-set matching, canonical duplicate rejection, enabled-state preservation, enabled-state mismatch rejection, and duplicate-state rejection).
- P2-43-R1 backup lifecycle source audit: 12 assertions passed.
- Existing P2-42-R24 lifecycle audit: 12 assertions passed.
- `Project.yml` YAML parse: passed.
- English and Simplified Chinese localization files: 519 unique keys each; no duplicate keys; key sets identical.
- Source ZIP integrity and SHA-256: verified after packaging.

## Added regression tests (source only)

- Schema 3 backup accepts case-variant Fixed Owner and Additional Association identity mirrors when topology and enabled bits agree.
- Schema 3 backup rejects case-variant duplicate Additional Associations.
- Restore preview recognizes an installed App when the installed Bundle ID differs only by case.

These XCTest source cases were added but were not executed in this environment.

## Not executed

- Full iOS or Helper Xcode build: unavailable in this Linux environment; `xcodebuild` is not present.
- XCTest execution: not run.
- Full `FilterKitBackupService` target type-check/build: not completed as a whole because the Apple project frameworks and app target dependency graph are unavailable here.
- Device export/restore acceptance, RootHide/ElleKit execution, signed Helper IPC, and real jailbreak filesystem tests: not run.

## R1 boundary

- This increment changes identity comparison and validation only; it does not change backup schema or rewrite stored Bundle ID strings.
- Duplicate canonical Bundle IDs and enabled-state mismatches remain fail-closed.
- Backup restore remains preview/selection only; no privileged restore commit was performed or enabled.
- Production injection, enable/disable, association mutation, and uninstall Gates remain closed.
