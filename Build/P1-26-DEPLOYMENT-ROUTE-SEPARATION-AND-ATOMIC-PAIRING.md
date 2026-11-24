# P1-26 — Deployment Route Separation & Atomic Pairing

## Scope delivered

P1-26 adds a Helper-side preflight layer for distinguishing first install from update and for treating a dylib plus its matching plist as one indivisible unit.

### Atomic batch validation

`HelperDeploymentBatchValidator` accepts exactly two operation records:

- one `installDylib` request;
- one `replaceFilterPlist` request;
- both must carry the same plugin UUID;
- request UUIDs must be distinct;
- basenames must match (case-insensitively);
- both staged paths and SHA-256 values must pass structural validation.

A partial pair, duplicate request ID, mismatched plugin ID, unsafe path, invalid hash, or mismatched basename is rejected.

### Route separation

`HelperDeploymentRouteResolver` selects one route for the entire pair:

| Existing FilterKit manifest | Root-side ownership evidence | Result |
|---|---|---|
| absent | verified unowned | first install |
| present | FilterKit owned | update |
| either | package-manager owned | reject |
| present | unowned / unknown | reject |
| absent | FilterKit owned / unknown | reject |

The resolver accepts an evidence classification, not a caller-supplied proof. Production integration must obtain that classification inside the Root Helper from `HelperPackageOwnershipResolver` and `HelperOwnershipProofVerifier`.

### Extension boundary

`HelperDeploymentRouteExecuting` defines a narrow route-specific preflight interface. The App process cannot supply a `HelperOwnershipProof` through IPC.

## Deliberately not enabled

This phase does **not** connect the new route resolver to `HelperRequestDispatcher` or `HelperRuntime`. P1-25's wire protocol carries one operation per envelope, while the safe executor requires a paired transaction. The current protocol therefore cannot safely submit an atomic pair as one authenticated request. No partial workaround was introduced.

The following remain false/disabled:

- `HelperDeploymentCoordinator.executionReleased`
- `HelperRequestDispatcher.executionReleased`
- root-owned manifest `executionEnabled`

No operation request reaches the bootstrap, ownership verifier, safe executor, or recovery mutator. Delete remains unavailable. Runtime startup recovery remains read-only.

## Verification

- Full project Swift syntax parse: PASS.
- Helper/runtime/execution source subset Linux typecheck: PASS.
- P1-26 routing smoke: PASS (atomic pair, first-install/update split, package-manager rejection, partial-pair rejection).
- Project configuration check: PASS.
- Architecture check: PASS.
- Localization parity: PASS (225 keys in each language; unchanged).
- ZIP integrity: PASS.

## Not run / not claimed

- XcodeGen or Xcode/iOS SDK build.
- XCTest execution.
- Darwin compilation or iOS AF_UNIX transport test.
- RootHide/Rootless device validation.
- launchd installation or CDHash pinning.
- Any real TweakInject write, update, deletion, or automatic recovery mutation.

## Required next protocol change

Before connecting dispatch, introduce a versioned `deploymentBatchRequest` envelope containing exactly two operation records and bind the batch digest, both request IDs, plugin UUID, session nonce, and timestamp to the authenticated connection. The Helper must then resolve route and ownership evidence itself, run one paired executor transaction, and return one batch receipt. Keep the release gate closed until that protocol and its Darwin/device tests pass.
