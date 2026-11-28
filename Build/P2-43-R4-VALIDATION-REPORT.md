# P2-43-R4 Validation Report

## Baseline

- Source baseline: `FilterKit-P2-43-R3-Source.zip`
- Verified SHA-256: `4ab157836532c3595da4e41db5cbd2ddee227c4225a5c500f70b62ea6e5681e0`
- `unzip -t` passed before extraction.
- Development performed in a fresh `FilterKit-P2-43-R4-Work/FilterKit-P2-42` directory. R3 archive and worktree were not modified.

## Executed checks

- Swift frontend syntax parse: all 246 Swift files under `Sources` and `Tests` parsed successfully.
- Activation-target policy Smoke executable: compiled and ran the actual `HelperBundleIdentifierKey`, Manifest association model, and `HelperAppPluginActivationTargetPolicy` sources; 5 assertions passed.
- Three-App association planner Smoke executable: compiled and ran the actual Bundle ID key, RootHide/ElleKit filter strategy, and Helper association mutation planner; 5 assertions passed. It verified removal of one enabled App while preserving another enabled App and one disabled App, and verified that a newly added relationship remains disabled and absent from Filter.plist.
- R4 APP/Plugin boundary static audit: 11 assertions passed.
- R3 first-install binding audit: 14 assertions passed.
- R2 lifecycle integration audit: 14 assertions passed.
- R1 backup lifecycle audit: 12 assertions passed.
- R24 lifecycle audit: 12 assertions passed.
- `Project.yml` YAML parse passed.
- English and Simplified Chinese localization files each contain 519 unique keys; no duplicate keys; key sets are identical.

## Not executed

- Full iOS / Helper Xcode build: unavailable in this Linux environment; no `xcodebuild` or Apple SDK.
- XCTest execution. New XCTest source was syntax-parsed but not run by XCTest.
- Full type-check of the complete Helper target and SwiftUI App target.
- Darwin-specific Helper IPC / filesystem integration tests.
- Signed RootHide / ElleKit device acceptance.
- Real plugin injection, activation, association mutation, uninstall, or restore.

## Safety boundary

The change tightens Helper authorization: APP activation cannot create Additional App Association topology. Plugin remains the only page allowed to add/remove associations; APP remains the only page allowed to enable/disable them.

All production write gates remain closed. No real plugin files or injection rules were modified during validation.
