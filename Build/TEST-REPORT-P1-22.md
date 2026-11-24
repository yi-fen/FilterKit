# P1-22 Test Report

## Passed

- Full project Swift parser check.
- Helper execution subset Foundation/POSIX typecheck on Linux.
- Paired dylib + plist transaction smoke test.
- Existing plist is replaced atomically on successful transaction.
- Exact staged byte preservation and SHA-256 verification.
- Existing dylib target conflict rejected.
- Tampered staged bytes rejected before target mutation.
- Staging symlink rejected by no-follow open.
- Plugin UUID mismatch against ownership proof rejected.
- Ownership proof rejects Schema 1/2 and unverified Mach-O identity.
- Helper target Project.yml includes execution module and SHA-256 implementation.
- Localization files unchanged; no new UI strings required.
- ZIP integrity check.

## Not run / not claimed

- XcodeGen project generation.
- Xcode/iOS SDK build or XCTest execution.
- Darwin/iOS compilation of `openat`/`renameat` implementation.
- RootHide or Rootless on-device validation.
- launchd Helper installation or startup.
- Real root Helper dispatch or TweakInject writes.

## Release gates retained

- `HelperDeploymentCoordinator.executionReleased == false`.
- Helper runtime still rejects all `operationRequest` messages.
- `HelperDeploymentManifest.disabledTemplate(...).executionEnabled == false`.
- Removal remains unavailable pending ownership-bound delete authorization.
