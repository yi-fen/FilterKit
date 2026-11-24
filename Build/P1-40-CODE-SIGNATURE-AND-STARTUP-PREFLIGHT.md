# P1-40 — Code Signature Identity & HelperRuntime Startup Preflight

## Scope

P1-40 strengthens Helper identity checks and makes startup recovery inspection explicit. It does not enable installation, activation, rollback, launchd operations, or plugin injection.

## Implemented

- `HelperCodeSignatureVerifier` validates the running Helper's kernel-reported 20-byte CDHash against the root-provisioned `allowedHelperCDHashes` pin set. Empty, malformed, and mismatched pins fail closed.
- On macOS tooling builds, `verifyStaticExecutable` uses Security.framework `SecStaticCodeCheckValidity` and compares the signing-information unique CDHash with the expected pin.
- Static executable verification intentionally returns `staticVerificationUnavailable` on iOS/Linux builds. iOS startup uses the running process CDHash obtained by the existing XNU `csops(CS_OPS_CDHASH)` integration; this is not a publisher/team identity check.
- `HelperRuntimePreflight` combines the running-CDHash check with `HelperStartupRecoveryCheck.inspectDetailed`. It is read-only and does not reconcile journals or touch TweakInject.
- `FilterKitHelperRuntime.run()` now invokes this preflight before constructing the IPC server. Existing dispatcher checks remain in place for per-request recovery status and deployment denial.
- `executionEnabled=false` and `HelperRequestDispatcher.executionReleased=false` remain unchanged.

## Security interpretation

A CDHash pin binds the process to bytes identified by the kernel's code-signing subsystem. It does not, by itself, prove an Apple Developer Team ID, certificate chain, notarization, or FilterKit publisher provenance. The current manifest pin provisioning must therefore remain installer-controlled and root-owned. The macOS static verifier checks code-signature validity and CDHash only; no designated requirement or publisher Team ID policy is claimed.

## Validation limits

Linux can validate the portable pin-matching logic and read-only preflight behavior. This environment cannot execute Security.framework or XNU `csops`; therefore no Darwin/iOS signature-verification success is claimed. Xcode/iOS build, macOS Security.framework compilation, jailbreak-device tests, and XCTest execution require their respective Apple environments.
