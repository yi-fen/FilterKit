# P1-26 Test Report

## Passed

- Full project Swift syntax parse with Linux Swift.
- Helper/runtime/execution source subset Foundation/POSIX typecheck on Linux.
- P1-26 routing smoke: atomic paired request accepted.
- P1-26 routing smoke: first-install route requires verified-unowned evidence.
- P1-26 routing smoke: update route requires FilterKit ownership evidence.
- P1-26 routing smoke: package-manager ownership rejected.
- P1-26 routing smoke: partial pair rejected.
- `bash Build/Scripts/verify-project-config.sh`: PASS.
- `python3 Build/Scripts/verify-architecture.py`: PASS.
- `python3 Build/Scripts/verify-localizations.py`: PASS (225 matching keys in both languages).
- ZIP integrity: PASS.

## Not run / not claimed

- XcodeGen generation, Xcode/iOS SDK build, XCTest execution.
- Darwin compilation or iOS AF_UNIX socket testing.
- RootHide/Rootless device validation.
- launchd install/bootstrap or Helper CDHash pinning.
- Dispatcher/runtime integration of the new paired batch protocol.
- Any real TweakInject write, update, deletion, or automatic recovery mutation.

## Release gates retained

- `HelperDeploymentCoordinator.executionReleased == false`.
- `HelperRequestDispatcher.executionReleased == false`.
- `HelperDeploymentManifest.disabledTemplate(...).executionEnabled == false`.
- Operation requests remain rejected by the runtime dispatcher.
- Unmanaged dylib removal remains unavailable.
