# P2-42-R23 Validation Report

## Baseline

- Source baseline: `FilterKit-P2-42-R22-Source.zip`
- Verified baseline SHA-256: `2a8d04f3f861a153fb8501d2f785dede8d1aaf9fc276275c9d1be2ff2086388e`
- Baseline ZIP integrity: `unzip -t` passed.
- R23 work was performed in a fresh extraction/work directory; R22 was not modified.

## Executed checks

- Swift frontend syntax parse: all 241 Swift files under `Sources` and `Tests` passed.
- Targeted Swift type-check: activation command/protocol/transaction record and reconciliation request models passed with a minimal stand-in for the unrelated deployment-batch validator.
- Protocol smoke executable: 3 assertions passed using the actual reconciliation request and status models. It checked confirmation-required validation and case-insensitive Bundle ID status matching.
- Transaction finalization smoke executable: 4 assertions passed using the actual `HelperPluginFilterConfigurationTransaction` implementation. It verified a pre-replacement rollback classification, rejection of mismatched hashes without Journal deletion, and successful cleanup only with exact observed hashes.
- R23 source audit: 10 assertions passed. It verifies that the status-query route contains no Ledger resolution or Journal finalization, the explicit reconciliation route persists the Ledger before Journal cleanup, the client request is allow-listed, the APP action is present, and the activation Commit gate remains closed.
- `Project.yml` YAML parse: passed.
- Localization: 519 unique keys in English and 519 in Simplified Chinese; no duplicates; key sets identical.

## Not executed

- Full iOS or Helper Xcode build: unavailable in this Linux environment; no `xcodebuild`.
- XCTest execution: not run. Added XCTest cases are source additions, not reported as passed.
- Full HelperRequestDispatcher target type-check/build: not completed as a whole because the Linux environment lacks project dependencies/frameworks (including ZIPFoundation and Apple-specific frameworks). Source syntax parsing passed.
- Darwin IPC transport, signed Helper identity, RootHide/ElleKit device execution, real process crash/restart, and jailbreak filesystem acceptance: not run.

## Release posture

The production APP activation Commit gate remains closed. No real plugin injection, enable/disable, association mutation, uninstall, or plugin-file recovery was performed. The new explicit reconciliation path is designed only to verify existing transaction evidence, persist a proven terminal Ledger state, and clean matching Journal artifacts after that persistence succeeds.
