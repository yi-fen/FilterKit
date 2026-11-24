# P1-27 — IPC Deployment Batch Protocol

## Goal

Replace the unsafe conceptual pattern of sending a dylib operation and a plist operation as two independent IPC messages with one versioned deployment-batch message. A batch is one protocol unit and always contains exactly one dylib install operation and one matching Filter.plist replacement operation.

## Implementation

- Added `deploymentBatchRequest` to `HelperIPCMessageType`.
- Added `HelperDeploymentBatchRequest` with `batchID`, `pluginID`, `createdAt`, the two operation records, and a SHA-256 digest.
- Digest is computed from sorted-key canonical JSON for the unsigned batch fields. Validation recomputes it and validates the exact paired operation shape.
- The batch UUID is also the IPC envelope request ID.
- The existing AF_UNIX transport accepts the new message type and continues to bind every request to a fresh handshake nonce.
- `HelperRequestDispatcher` validates session binding, freshness, batch identity, pair shape, digest, and replay protection for both the batch ID and nested operation IDs.
- The dispatcher then rejects with `execution_disabled`; it does not call the route resolver, ownership verifier, transaction executor, or filesystem mutation path.
- `HelperDeploymentCoordinator.makeBatchEnvelope` creates the single-envelope request. `submitBatch` remains blocked by the independent App-side release gate.

## Security properties

- Partial batches, mismatched plugin IDs, duplicate operation IDs, unsafe names/paths, mismatched dylib/plist basenames, stale timestamps, and altered batch payloads are rejected.
- Rewrapping previously accepted operation IDs in a new batch ID is rejected by nested replay checks.
- No client-supplied ownership proof is accepted.
- No real TweakInject write, update, deletion, or automatic recovery is enabled.

## Verification

- Full Swift syntax parse: PASS.
- Helper/runtime/execution Linux Foundation/POSIX typecheck: PASS.
- P1-27 batch protocol smoke: PASS (paired validation, canonical digest, tamper rejection).
- Project identity/signing configuration: PASS.
- Architecture structure check: PASS.
- Localization parity: PASS (225 keys in each language).
- ZIP integrity: PASS.

## Not run

- XcodeGen, Xcode/iOS SDK build, XCTest execution.
- Darwin/iOS AF_UNIX runtime validation.
- RootHide/Rootless device validation.
- End-to-end route authorization and real filesystem executor dispatch.

## Release gates

- `HelperDeploymentCoordinator.executionReleased == false`.
- `HelperRequestDispatcher.executionReleased == false`.
- `HelperDeploymentManifest.disabledTemplate(...).executionEnabled == false`.
- The runtime does not invoke first-install/update authorization or `HelperSafeFileExecutor`.
- Dylib removal remains unavailable.
