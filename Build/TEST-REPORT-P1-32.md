# Test Report — P1-32

## Passed

- Full Swift syntax parse across `Sources`, `App`, `HelperRuntime`, and `Tests`.
- Helper + Runtime + Execution + IPC models Linux Swift typecheck (excluding the backup restore-only `HelperDeploymentPlanBuilder` / `HelperDeploymentWriter` source pair whose backup domain models are built in the app target).
- P1-32 Linux Root smoke: structured health response for clean plugin directory.
- P1-32 Linux Root smoke: invalid three-file journal is exposed as `invalidJournal` over health IPC.
- P1-32 Linux Root smoke: authenticated maintenance `inspect` request returns current status.
- P1-32 Linux Root smoke: `reconcileThreeFileTransaction` returns `recoveryNotReleased`.
- P1-32 Linux Root smoke: maintenance request replay is rejected.
- P1-32 Linux Root smoke: maintenance request is audited.
- P1-32 Linux Root smoke: deployment batch is rejected with `invalid_transaction_journal` when journal is invalid.
- P1-32 Linux Root smoke: maintenance request performs no filesystem mutation.
- Project configuration check.
- Architecture check.
- Localization parity: 237 matching `zh-Hans` / `en` keys.

## Not run / not claimed

- XcodeGen generation or Xcode/iOS SDK build.
- XCTest execution (new XCTest coverage added but not run).
- SwiftUI/iOS compile of the Settings UI.
- Darwin compilation or iOS code-signing/CDHash validation.
- App-side production transport configuration; Settings shows “Not configured” until coordinator injection.
- launchd Helper installation/bootstrap.
- RootHide/Rootless on-device validation.
- Actual TweakInject writes or recovery mutation.
- Real device power-loss testing.

## Release gates retained

- `HelperRequestDispatcher.executionReleased == false`.
- `HelperDeploymentCoordinator.executionReleased == false`.
- `HelperProductionDeploymentBackend.executionReleased == false`.
- Helper deployment manifest template remains `executionEnabled == false`.
- Pending/invalid recovery state allows authenticated status-only IPC; deployment requests are rejected.
- App maintenance reconcile requests cannot mutate files and return `recoveryNotReleased`.
- Plugin deletion remains unavailable.
