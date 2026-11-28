# P2-43-R17 — Recovery Acceptance Runner

## Scope

R17 connects the recovery acceptance path to the existing R10–R15 components without opening production write permissions.

## Changes

- Added `HelperInstallerRecoveryAcceptanceRunner`.
- The runner invokes `HelperInstallerRecoveryPreflight.inspectTwiceUnderSharedLock`, so the existing Durable Journal Store, descriptor filesystem reconciliation backend, and shared persistent transaction lock are used by the acceptance path.
- Added an explicit bridge to `HelperInstallerAuthenticatedServiceObserver.validate`. The caller must supply the peer identity obtained from the authenticated transport layer and a fresh one-time challenge for each observation pass.
- Added deterministic JSON acceptance reports containing Journal sequence/head, Active/Staged/Previous artifact inventories, SHA-256, byte count, UID/GID, mode, device/inode, active pointer identity, ownership result, service observer identity, and service state.
- The report digest is a deterministic diagnostic fingerprint only. It is not a signature, credential, or execution capability.
- Human review can bind to the report digest through the existing review-only authorization API. Execution authorization remains unavailable.
- Added unit tests for report JSON round-trip and non-authorizing report semantics.

## Deliberately not enabled

- No filesystem mutation or launchd control was added.
- No production install, activation, recovery, rollback, or service-start gate was opened.
- The actual Darwin launchd observer and authenticated XPC transport adapter remain platform integration requirements; the runner accepts observations only after the caller validates them through the R15 observer bridge.
- No claim is made that this Linux host run is an iOS/Helper end-to-end runtime test.
