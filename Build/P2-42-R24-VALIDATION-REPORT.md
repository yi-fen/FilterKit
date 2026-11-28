# P2-42-R24 Validation Report

## Baseline

- Source baseline: `FilterKit-P2-42-R23-Source.zip`
- Verified baseline SHA-256: `78ca99df114e2dfc3166d58e1d69a97251c04a247bc2a0e63dd0b7c4503fd3ac`
- Baseline ZIP integrity: `unzip -t` passed.
- R24 was developed in a fresh extraction/work directory; R23 was not modified.

## Executed checks

- Swift frontend syntax parse: all 241 Swift files under `Sources` and `Tests` passed.
- Targeted Swift executable compiled and ran using the actual activation Ledger model and `HelperAppPluginActivationTransactionLedgerStore` source, with minimal stubs for unrelated policy/model dependencies.
- Ledger smoke: 4 assertions passed: insert/read round trip, case-insensitive Bundle ID lookup, creation and `0600` mode of the stable lock file, and fail-closed capacity without evicting existing history.
- Multi-process Ledger smoke: two concurrently released child processes inserted distinct command records through separate Store instances; both records were retained (no lost update).
- R24 lifecycle source audit: 12 assertions passed, covering the stable flock lock, capacity policy, recovery-hint persistence/restore, dispatcher serialization, scan-only dismissal behavior, and closed production gate.
- `Project.yml` YAML parse: passed.
- Localization: 519 unique keys in English and 519 in Simplified Chinese; no duplicates; key sets identical.
- Source ZIP integrity and SHA-256: verified after packaging.

## Not executed

- Full iOS or Helper Xcode build: unavailable in this Linux environment; no `xcodebuild`.
- XCTest execution: not run. New XCTest source cases are not reported as executed.
- Full HelperRequestDispatcher target type-check/build: not completed as a whole because Apple frameworks and project dependencies are unavailable in this environment.
- Multi-process Darwin Helper concurrency, signed IPC identity, RootHide/ElleKit device execution, App process termination/relaunch on device, and real jailbreak filesystem acceptance: not run.

## R24 design boundary

- App-side persisted command data is a recovery hint only. It does not authorize a mutation and cannot establish transaction success. Helper must still match the command ID, Plugin ID, Bundle ID, Ledger, Journal, and file hashes.
- Scan-only observations do not clear an unresolved command. Only a Helper-confirmed terminal state clears the hint.
- Ledger capacity uses fail-closed retention. No automatic archive or deletion of terminal records is performed.
- Production APP activation Commit remains disabled. No real plugin injection, enable/disable, association mutation, uninstall, or file recovery was performed.
