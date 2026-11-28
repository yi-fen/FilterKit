# P2-45-R1 — Darwin Production Build & Signing Qualification

## Scope

R1 establishes the first production-environment qualification boundary. It adds a macOS-only, read-only preflight for Xcode/iOS SDK availability and an unsigned compile-only Release build. It does not install, launch, activate, mutate jailbreak files, change code-signing policy, or open any production write gate.

## Findings from the inherited project configuration

- App target: `cn.yfen.filterkit`, Automatic signing, no hard-coded Development Team.
- Helper target: `cn.yfen.filterkit.helper`, Manual signing style but `CODE_SIGNING_ALLOWED=NO`. This is an explicit release blocker: the current target configuration does not produce a signed Helper release artifact through the declared Xcode build settings.
- Existing release identity extraction expects a final signed Helper executable and Apple `codesign` metadata. The final signing path for the jailbreak Helper must be defined and validated against the actual deployment format before R1 can pass.
- Production execution gates remain false in HelperRequestDispatcher, HelperDeploymentCoordinator, and HelperProductionDeploymentBackend. Provisioning keeps `executionEnabled=false`; test-only activation execution injection defaults false.

## Validation

`p245_r1_static_audit.py` checks the configuration and write-gate invariants without modifying them.
`p245_r1_darwin_build_signing_preflight.sh` must run on macOS with Xcode, xcodegen, codesign, and security. It performs an unsigned compile-only build and deliberately exits as BLOCKED after that build because a compile product is not a signed release artifact.

## Status

**R1 BLOCKED / NOT RELEASE-QUALIFIED.** This execution environment is Linux and cannot run Apple Xcode, iOS SDK, codesign, provisioning, or device checks. The Helper target's explicit `CODE_SIGNING_ALLOWED=NO` is an additional source-level blocker. No production write gate was changed.

## P2-45 roadmap / write-enable decision

P2-45 is not a single switch flip. Planned qualification gates:

1. R1 Darwin/Xcode build and signing qualification (this phase; currently blocked).
2. R2 Helper identity, entitlement, launchd job and XPC/peer-credential qualification on macOS/device.
3. R3 RootHide filesystem ownership, permissions, fd-relative replacement and Darwin crash semantics.
4. R4 disposable-device install/upgrade/rollback/reboot/power-interruption acceptance.
5. R5 narrow canary write enablement for FilterKit-owned test plugins only, after signed release, identity, recovery and device evidence are reviewed.
6. R6 end-to-end injection/disable/uninstall acceptance and staged expansion decision.

No phase may infer R5 authorization from Host tests alone. R1 specifically does not alter `CODE_SIGNING_ALLOWED`, production gate constants, provisioning defaults, HelperRuntime wiring, or launchd state.
