# P1-25 Test Report

## Passed

- Helper/runtime/execution Swift source subset typecheck with Linux Swift.
- P1-25 dispatcher smoke: health request accepted for a valid session nonce.
- P1-25 dispatcher smoke: incorrect session nonce rejected.
- P1-25 dispatcher smoke: malformed operation payload rejected.
- P1-25 dispatcher smoke: structurally valid install request denied by the closed execution gate.
- P1-25 dispatcher smoke: repeated request ID rejected by replay guard.
- P1-25 dispatcher smoke: operation denial produces a stable audit reason code.
- Both App-side and Helper-side execution release gates remain false.
- `bash Build/Scripts/verify-project-config.sh`: PASS.
- `python3 Build/Scripts/verify-architecture.py`: PASS.
- `python3 Build/Scripts/verify-localizations.py`: PASS (225 matching keys in both languages).
- Full Swift syntax parse across project Swift sources: PASS.
- ZIP integrity: PASS.

## Not run / not claimed

- XcodeGen generation, Xcode/iOS SDK build, XCTest execution.
- Darwin compilation of AF_UNIX transport and socket-option constants.
- End-to-end client/server socket test on iOS.
- RootHide/Rootless device validation.
- launchd install/bootstrap, Helper CDHash pinning, actual TweakInject writes.
- Real operation dispatch to first-install bootstrap, package ownership resolver, ownership verifier, or safe file executor.
- Automatic startup recovery mutation.

## Release gates retained

- `HelperDeploymentCoordinator.executionReleased == false`.
- `HelperRequestDispatcher.executionReleased == false`.
- `HelperDeploymentManifest.disabledTemplate(...).executionEnabled == false`.
- All operation requests are rejected by the runtime dispatcher.
- Unmanaged dylib removal remains unavailable.
