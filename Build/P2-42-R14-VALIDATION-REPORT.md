# P2-42-R14 Validation Report

## Executed in this environment

- `swiftc -frontend -parse` across all 230 Swift files under `Sources` and `Tests`: PASS.
- Compiled and executed the actual `HelperPluginAssociationFilterMutationPlanner` with the actual `RootHideElleKitFilterStrategy` in a standalone Swift harness: 4 scenarios PASS (multi-App removal, fixed owner disabled, disabled association removal, alternate filter dimension refusal).
- Compiled and executed the actual `HelperThreeFileUninstallTransaction` and `SHA256Digest` in a standalone root-owned filesystem harness: 6 scenarios PASS (all five journal phases plus last-boundary authorization denial).
- Compiled and executed the actual `HelperPluginFilterConfigurationTransaction` in an isolated dependency harness: schema-3 to schema-4 fixed-owner-disabled commit PASS; staged topology and Filter.plist target consistency validated.
- Isolated Swift typecheck of the two-file transaction and its schema-4 validation helpers: PASS.
- `Project.yml` YAML parse: PASS.
- zh-Hans/en localization: 510 keys each, no duplicate keys, key sets match.
- Static release-gate audit: deployment, association commit, APP activation commit, and uninstall execution remain closed.
- Static Plugin-page audit: no per-App activation mutation API references in `PluginsView.swift`.
- ZIP integrity: checked after packaging.

## Not executed

- XCTest target was not run: this Linux environment has Swift 6.2.1 but no `xcodebuild` / iOS SDK.
- Full iOS app/Helper target compilation was not run.
- RootHide / ElleKit device tests were not run.
- The newly added XCTest cases are committed as source but are not reported as executed.

## Release decision

R14 is an offline source and transaction-hardening milestone only. Do not enable production write gates based on these results. A signed iOS/Helper build, device-side ownership/authorization tests, and actual crash/recovery acceptance remain prerequisites.
