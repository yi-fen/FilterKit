# P2-42-R11 Validation Report

## Executed

- Swift frontend syntax parse: all 228 Swift files under `Sources` and `Tests` passed.
- Compiled and executed a standalone Swift harness using the actual `PluginListScope.swift`: 5 assertions passed, covering Fixed Owner priority, case-insensitive deduplication, per-App counts, ambiguous duplicate-state fallback, global wildcard fallback, and exclusion of external ownership from the FilterKit-only scope.
- Localization: 510 keys in each language, no duplicate keys, identical key sets.
- `Project.yml`: YAML parse passed.
- ZIP integrity: checked after packaging.

## Not executed / limitations

- Full iOS build and XCTest were not run because this Linux environment has no Xcode / `xcodebuild` and does not provide the iOS SDK.
- SwiftUI runtime/layout verification and RootHide / ElleKit device validation were not run.
- No production injection, per-App toggle, association commit, uninstall, or backup restore was performed.

## Gate status

All production mutation gates remain closed.
