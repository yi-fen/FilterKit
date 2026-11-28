# P2-42-R13 Validation Report

## Executed

- Swift parser: all 230 Swift files under `Sources` and `Tests` parsed successfully with Swift 6.2.1.
- Targeted typecheck: Helper association planner, Helper mutation wire model, and RootHide ElleKit filter strategy typechecked successfully (using a minimal temporary HelperPolicy stub only to satisfy unrelated static validation references in the wire model).
- Executable Swift smoke test: active Additional App Association removal removed its Bundle from the proposed Filter.plist; new associations remained disabled; ambiguous Classes-based matching was rejected for both enabled and disabled associations (4 assertions/scenarios).
- Injection-default source check: `PluginImportBatchPolicyStore.beginBatch` still sets `defaultsEnabled = true`; first-batch Fixed Owner and later first-time target-App associations are created enabled by default. Regression assertions were added to the unit-test source but XCTest was not run.
- Source inspection: Plugin page contains no activation Toggle and no activation-bit mutation operation; APP activation UI remains in Apps feature.
- Release switches inspected and remain `false`.
- Project.yml YAML parse and localization key parity checked.
- Source archive passed `unzip -t`; SHA-256 recorded at packaging.

## Not executed

- No Xcode / `xcodebuild` is available in this Linux environment. Full iOS app/helper target compilation and XCTest were not run.
- No RootHide / ElleKit device test or real privileged Helper transaction was run.
- Production uninstall and mutation execution remain gated off.

## Important runtime note

Three-file uninstall prevents future launches from loading the removed plugin. A process that already mapped the dylib may keep it loaded until that process exits or restarts; the Helper does not attempt unsafe cross-process image unloading.
