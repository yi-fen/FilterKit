# P2-36-R2 Phase 4 — Apple Platform Build & RootHide Device Acceptance

## Scope and current status

Phase 4 is the Apple-platform and target-device acceptance gate. This delivery adds a stricter, reproducible macOS validation entry point and expands the Darwin SDK importer probe. It does **not** claim that Apple SDK compilation, XCTest, code signing, deployment, or RootHide device execution has passed: this work session is running on Linux and has no Xcode, Apple SDK, signing identity, or attached RootHide/ElleKit device.

## What was prepared

- `Build/DarwinSDK/FilterKitDarwinSDKProbe.swift` now typechecks the Swift importer surface for `getpeereid`, `LOCAL_PEERPID`, `LOCAL_PEERTOKEN`, `csops(CS_OPS_CDHASH)`, and the existing `libproc` usage.
- `Build/Host/run-p236r2-phase4-apple-validation.sh` requires macOS/Xcode/XcodeGen, probes both iPhoneOS and Simulator SDKs, builds Helper and App for Simulator, runs XCTest, then performs generic iPhoneOS Helper and App builds with signing disabled.
- `Build/scripts/p236r2_phase4_apple_gate_audit.py` checks the security invariants and confirms both production association gates remain closed.

## Host-side verification performed in this delivery

- Phase 2 transaction audit: 17/17 passed.
- Phase 2 transaction Host Smoke: passed, including six journal phases and subprocess SIGKILL recovery.
- Phase 3 integration audit: 18/18 passed.
- Phase 3 live AF_UNIX Host integration Smoke: passed; it uses fixture identity and Linux `SO_PEERCRED`, not Darwin kernel identity.
- Swift parser over `Sources`, `App`, `HelperRuntime`, `Tests`, and Host Swift files: passed.
- Phase 4 Apple gate audit: expected to run on this host; result recorded in the delivery report.
- Apple SDK probe / Xcode / XCTest: BLOCKED, NOT RUN on Linux.

## Required macOS execution

Install a supported Xcode with iOS SDKs and XcodeGen, boot an iOS Simulator, then run:

```sh
xcrun simctl list devices available
FILTERKIT_SIMULATOR_UDID="<booted simulator UDID>" \
  Build/Host/run-p236r2-phase4-apple-validation.sh
```

The script writes logs and `.xcresult` under `Build/Artifacts/`. Preserve those artifacts and review all compiler warnings, linker output, and test failures; do not infer success from the script existing.

## Required signed RootHide device acceptance (manual, not performed)

Only after successful macOS builds and a separately reviewed signing/provisioning setup:

1. Build and sign App and Helper using the project's trusted release pipeline. Do not use ad-hoc signatures as production identity evidence.
2. Verify both signatures and record the actual App and Helper CDHashes from the final installed artifacts. Confirm the root-owned trust manifest pins those exact hashes and the App trust payload pins the Helper hash.
3. Deploy through the established RootHide Helper installer/lifecycle path. Do not manually replace privileged files or bypass the installer transaction.
4. On the target device, launch the signed App and perform only a read-only Health IPC request first. Preserve sanitized Helper diagnostics showing peer UID/GID/PID, audit-token evidence presence, and matched pin identifier; never log raw audit-token bytes or full sensitive process metadata.
5. Confirm `LOCAL_PEERTOKEN` is returned with the expected size on the actual target OS; confirm its euid/egid/pid fields match `getpeereid` and `LOCAL_PEERPID`; confirm the same token snapshot remains stable across the `csops(CS_OPS_CDHASH)` call.
6. Confirm the kernel-reported peer CDHash matches the provisioned pin. Test a separately signed negative client and a same-UID/GID client with a different CDHash; both must be rejected before dispatch.
7. Restart Helper and App separately and repeat the Health handshake. Confirm no stale PID/session identity is accepted.
8. Verify startup recovery behavior using a test-only transaction fixture on device, not production Filter.plist. Do not induce a crash while real user configuration is being changed.
9. Attach device model, iOS version, RootHide/ElleKit version, signed artifact hashes, sanitized logs, and pass/fail results to the acceptance report.

## Release gate

`HelperDeploymentCoordinator.pluginAssociationCommitReleased` and `HelperRequestDispatcher.pluginAssociationCommitReleased` must remain `false`. Phase 4 is not complete until the Apple SDK builds, XCTest, signed identity checks, and RootHide device evidence are reviewed. No production soft-association write or plugin injection is authorized by this phase.
