# P2-42-R22 Validation Report

## Baseline

- Source baseline: `FilterKit-P2-42-R21-Source.zip`
- Verified baseline SHA-256: `69f4eadfe6fceeeb022a79feac2f6e58f054be07748bfa8a1ec6371506ddd10c`
- Baseline ZIP integrity: `unzip -t` passed.
- R22 was extracted into a new work directory before modifications.

## Executed checks

- Swift frontend syntax parse: all 241 Swift files under `Sources` and `Tests` passed.
- Targeted Swift type-check: activation transaction, ledger record/store, protocol models, SHA implementation, and supporting models type-checked with a minimal stand-in for the unrelated mutation-authorizer dependency.
- Transaction smoke executable: 7 assertions passed using the actual `HelperPluginFilterConfigurationTransaction`, `FilterKitPluginManifest`, `HelperBundleIdentifierKey`, and `SHA256Digest` source files. It exercised retained committed journal evidence, journal finalization, verified previous-byte evidence, and a mixed two-file state remaining unknown. A minimal stub supplied the unrelated mutation-authorizer data carrier.
- Durable ledger smoke executable: 2 assertions passed using the actual activation record and ledger store. A mismatched after-hash was rejected while the record remained `Outcome Unknown`; the exact after-hash pair then resolved it to `Committed`.
- Project.yml YAML parse: passed.
- Localization consistency: 512 unique keys in each of English and Simplified Chinese; no duplicate keys; key sets identical.

## Not executed

- Full iOS or Helper target build: unavailable because this Linux environment has no Xcode/`xcodebuild` and does not provide SwiftUI.
- XCTest execution: not run. The new XCTest cases are source additions, not reported as passed.
- Darwin-specific Helper IPC, RootHide/ElleKit device execution, real Helper process crash/restart, code-signing, and jailbreak-device filesystem validation: not run.

## Release posture

The production activation execution gate remains closed. This stage did not perform real plugin injection, enable/disable, association mutation, uninstall, or automatic filesystem recovery.
