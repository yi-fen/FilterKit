# P1-25 — Helper Request Dispatch & Session Binding

## Scope

P1-25 integrates a single request-dispatch boundary into the Helper runtime while retaining the global execution release gate. It does not enable deployment, deletion, or automatic startup recovery.

## Changes

- Added `HelperRequestDispatcher` as the single place for request freshness, authenticated peer/session consistency, per-connection nonce binding, replay protection, operation payload decoding, structural validation, release-gate evaluation, and request-level audit decisions.
- Health checks return a nonce-bound health response only after the session and request freshness checks pass.
- Operation requests must match the envelope request ID, use a recent timestamp, contain a nonzero plugin UUID, use a safe leaf filename and safe staging-relative path, and provide a syntactically valid SHA-256.
- Removal requests remain structurally denied; no unmanaged deletion path is introduced.
- Every operation request is rejected while either `HelperRequestDispatcher.executionReleased` or the root-owned manifest's `executionEnabled` is false. A second fail-closed branch remains even if both bits are changed in a test build; the privileged executor is not yet wired.
- Added stable machine-readable rejection codes. Audit records contain request metadata and reason codes only, never request payloads or plugin bytes.
- The client now copies the fresh handshake nonce into its request envelope. The server verifies that the request carries the exact nonce from that connection's hello challenge.
- Moved replay protection from the generic socket loop into the dispatcher so replay decisions are part of the centralized request policy.
- `HelperRuntime` now routes authenticated requests through the dispatcher instead of maintaining a separate inline switch.

## Security behavior

- Peer credentials and CDHash trust are still established by the existing platform identity provider and trust policy before dispatch.
- Session nonce, peer identity fields, and authentication time are rechecked at dispatch.
- Invalid, stale, replayed, malformed, and disallowed requests fail closed.
- Audit failure never grants permission to execute an operation.
- `HelperDeploymentCoordinator.executionReleased == false`.
- `HelperRequestDispatcher.executionReleased == false`.
- `HelperDeploymentManifest.disabledTemplate(...).executionEnabled == false`.
- The runtime still does not call `HelperSafeFileExecutor`, first-install bootstrap, package ownership resolver, or recovery mutation as part of an operation request.

## Verification

- Helper/runtime/execution source subset Linux Swift typecheck: PASS.
- P1-25 dispatcher smoke: PASS (health request, nonce mismatch, malformed payload, replay, operation denial, audit reason, closed release gates).
- Project configuration, architecture, localization parity, and ZIP integrity checks: run separately and recorded in `TEST-REPORT-P1-25.md`.

## Not run / not claimed

- XcodeGen generation or Xcode/iOS SDK build.
- XCTest execution.
- Darwin compilation or actual iOS AF_UNIX socket handshake.
- RootHide/Rootless device verification.
- launchd installation, CDHash pinning, or real TweakInject writes.
- Production operation execution or deletion.
