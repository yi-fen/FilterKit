# P2-42-R15 Validation Report

## Baseline

- Input: `FilterKit-P2-42-R14-Source.zip`
- Input SHA-256: `73736a05b4393be05ad78c692c5a10e88f8a524d61d55160ae2e572c3146607a`
- Input archive passed `unzip -t` before extraction.

## Executed checks

- `swiftc -frontend -parse` across all Sources and Tests Swift files: passed (231 Swift files after R15 additions).
- Compiled and executed a standalone Swift lifecycle harness against the production topology, import-policy, Helper mutation model, RootHide filter strategy, and association planner sources: 4/4 scenarios passed.
  - Removing an enabled App association removes its Bundle filter target.
  - Other enabled App targets and Fixed Owner remain unchanged.
  - A new Plugin-page association defaults disabled and is absent from active Bundle targets.
  - A disabled Fixed Owner remains disabled; unsafe alternate Classes matching blocks removal.
- `Project.yml` YAML parse: passed; targets include FilterKit, FilterKitHelper, FilterKitTests.
- Localization audit: English 510 keys, Simplified Chinese 510 keys, no duplicate keys, identical key sets.
- Release-gate source audit: `HelperDeploymentCoordinator.pluginAssociationCommitReleased == false`, `HelperRequestDispatcher.pluginAssociationCommitReleased == false`, and `pluginUninstallExecutionReleased == false`.
- ZIP archive integrity: checked separately after packaging.

## Not executed / limitations

- Xcode is unavailable in this Linux environment; full iOS build and XCTest execution were not run.
- No signed Helper installation, jailbreak device, RootHide/ElleKit runtime, live IPC, or on-device transaction fault injection was available.
- The standalone harness validates pure model/planner behavior, not a real filesystem commit.

## Safety conclusion

R15 improves offline lifecycle consistency and refresh behavior only. It does not release production mutation gates or claim real-device injection, association commit, or uninstall success.
