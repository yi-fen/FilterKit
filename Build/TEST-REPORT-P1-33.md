# Test Report — P1-33

## Passed

- Full Swift syntax parse across `Sources`, `App`, `HelperRuntime`, and `Tests`.
- Helper + Runtime + Execution + IPC models Linux Swift typecheck.
- Trust smoke: exact installer pin set accepted.
- Trust smoke: disabled Helper manifest generated from provisioned pins.
- Trust smoke: generated manifest pins match installer pin set.
- Trust smoke: App-bundled trust config contains Helper pin without self-referential App CDHash.
- Trust smoke: empty and malformed pin sets rejected.
- Trust smoke: root App UID rejected.
- Trust smoke: case-insensitive duplicate CDHashes rejected.
- Trust smoke: execution remains disabled.
- Project configuration check.
- Architecture check.
- Localization parity: 237 matching `zh-Hans` / `en` keys.
- ZIP integrity.

## Not run / not claimed

- XcodeGen generation or Xcode/iOS SDK build.
- XCTest execution (new XCTest coverage added but not run).
- Darwin compilation of the `#if canImport(Darwin)` App transport factory.
- Actual App bundle CDHash / Helper CDHash extraction on iOS.
- `csops(CS_OPS_CDHASH)`, `LOCAL_PEERPID`, `getpeereid` device validation.
- Trusted installer provisioning and root-owned manifest installation.
- App composition-root injection and live Settings status query.
- launchd Helper installation/bootstrap.
- RootHide/Rootless device validation or real TweakInject writes.

## Release gates retained

- `HelperRequestDispatcher.executionReleased == false`.
- `HelperDeploymentCoordinator.executionReleased == false`.
- `HelperProductionDeploymentBackend.executionReleased == false`.
- Helper deployment manifest template remains `executionEnabled == false`.
- Maintenance recovery mutation remains `recoveryNotReleased`.
- Plugin deletion remains unavailable.
