# P2-43-R2 Validation Report

## Baseline

- Source baseline: `FilterKit-P2-43-R1-Source.zip`
- Verified baseline SHA-256: `bf6380907ca30a917bad27ba6a7bfa2ab2b9cb12641fc6c212dc35f99bb84378`
- Baseline ZIP integrity: `unzip -t` passed.
- Development used a fresh copy at `FilterKit-P2-43-R2-Work/FilterKit-P2-42`; R1 was not modified.

## Executed checks

- Swift frontend syntax parse: all 242 Swift files under `Sources` and `Tests` passed.
- Targeted Swift executable compiled and ran the actual `HelperBundleIdentifierKey.swift`, `PluginLifecyclePolicy.swift`, and `PluginBindingTopology.swift` sources. Minimal stubs supplied unrelated ownership/import model dependencies. 12 lifecycle assertions passed.
- P2-43-R2 lifecycle integration source audit: 14 assertions passed.
- P2-43-R1 backup lifecycle audit: 12 assertions passed.
- P2-42-R24 lifecycle audit: 12 assertions passed.
- `Project.yml` YAML parse: passed.
- English and Simplified Chinese localization files: 519 unique keys each, no duplicates, identical key sets.
- Source ZIP integrity and SHA-256: verified after packaging.

## Added regression tests (source only)

- Case-insensitive installed/unavailable association projection with original Manifest spelling retained.
- Canonical per-App enabled-state lookup.
- Case-insensitive Fixed Owner and Additional Association add/remove policy.
- Removing one enabled association from a three-App topology preserves the other enabled and disabled states.

These XCTest source cases were syntax-parsed but were not executed as XCTest in this environment.

## Not executed

- Full iOS or Helper Xcode build: unavailable in this Linux environment; `xcodebuild` is not present.
- XCTest execution: not run.
- Full SwiftUI app target type-check/build: not completed.
- RootHide/ElleKit device acceptance, signed Helper IPC, and real jailbreak filesystem mutation tests: not run.

## R2 boundary

- This increment fixes lifecycle identity comparison and APP pending-operation row matching only.
- It does not change backup schema, Helper transaction protocol, ownership proof, or package-manager ownership policy.
- Production injection, enable/disable, association mutation, restore, and uninstall Gates remain closed.
- No real plugin files, Filter.plist, Manifest, or Helper transaction records were modified on a jailbreak device.
