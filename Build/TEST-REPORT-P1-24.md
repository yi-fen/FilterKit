# P1-24 Test Report

## Passed

- Full Swift parser check across App, Sources, HelperRuntime, and UnitTests.
- Helper runtime/execution source subset typecheck with Linux Swift 6.2.1.
- P1-22 executor smoke regression.
- P1-23 ownership verifier smoke regression.
- P1-23 transaction journal/recovery planner smoke regression.
- P1-24 package ownership resolver: exact dpkg-owned path denied; verified-unowned evidence produced only after scanning a root-owned info directory.
- First-install authorization: authenticated peer context, package proof, valid Mach-O identity and plist produce a root-owned Schema 3 manifest.
- Exact same-manifest retry returns the same proof; manifest overwrite is not permitted.
- First-install paired deployment through the existing fd-relative executor.
- Deployed manifest and payloads pass the independent ownership verifier.
- First-install proof refuses to replace an already existing plist.
- Startup gate reports pending journal, then clean after successful recovery.
- Recovery executor rolls back a simulated interrupted transaction, restores exact old plist bytes, removes exact matching new dylib/temp bytes, clears the journal, and is clean on the next check.
- `verify-project-config.sh`: PASS.
- `verify-architecture.py`: PASS.
- `verify-localizations.py`: PASS, 225 matching keys in both languages.
- ZIP integrity: PASS.

## Not run / not claimed

- XcodeGen generation, Xcode/iOS SDK build, XCTest execution.
- Darwin/iOS compilation of POSIX calls.
- Real RootHide/Rootless dpkg info-directory profile validation.
- Production Helper IPC operation dispatcher integration.
- Automatic recovery mutation during startup.
- launchd installation or Helper CDHash pinning on device.
- Actual TweakInject writes on a jailbreak device.

## Release gates retained

- `HelperDeploymentCoordinator.executionReleased == false`.
- Helper runtime rejects all operation requests.
- `HelperDeploymentManifest.disabledTemplate(...).executionEnabled == false`.
- Unmanaged dylib removal remains denied.
