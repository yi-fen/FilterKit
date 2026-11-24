# P1-27 Test Report

## Passed

- Full project Swift syntax parse with Linux Swift.
- Helper IPC models, deployment models, route resolver, SHA-256, Mach-O metadata and helper execution/runtime subset typecheck on Linux.
- P1-27 standalone batch protocol smoke: paired validation, canonical digest generation and tamper rejection.
- `bash Build/Scripts/verify-project-config.sh`: PASS.
- `python3 Build/Scripts/verify-architecture.py`: PASS.
- `python3 Build/Scripts/verify-localizations.py`: PASS (225 matching keys in both languages).
- ZIP integrity: PASS.

## Added but not executed

- `HelperDeploymentBatchProtocolTests.swift` covers digest tampering, partial pair rejection, dispatcher closed-gate behavior, nested operation replay protection and coordinator envelope construction. XCTest was not run in this environment.

## Not run / not claimed

- XcodeGen generation, Xcode/iOS SDK build, XCTest execution.
- Darwin compilation or iOS AF_UNIX socket testing.
- RootHide/Rootless device validation.
- End-to-end first-install/update route authorization wired to the dispatcher.
- `HelperSafeFileExecutor` dispatch from the IPC runtime.
- Any real TweakInject write, update, deletion, or automatic recovery mutation.

## Release gates retained

- `HelperDeploymentCoordinator.executionReleased == false`.
- `HelperRequestDispatcher.executionReleased == false`.
- `HelperDeploymentManifest.disabledTemplate(...).executionEnabled == false`.
- Standalone legacy operation requests remain non-executable; batch requests validate as one unit but are rejected before execution.
- Unmanaged dylib removal remains unavailable.
