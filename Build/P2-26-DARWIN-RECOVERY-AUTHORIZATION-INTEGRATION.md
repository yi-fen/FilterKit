# P2-26 — Darwin Recovery Authorization Integration & Device Validation Preflight

## Scope

P2-26 corrects the maintenance authorization boundary for the actual FilterKit architecture: the Helper is the privileged root process, while the FilterKit App is an unprivileged IPC peer. P2-25 required the connected peer itself to have UID 0, which made its authorization capability unusable through the ordinary App-to-Helper channel.

This phase integrates transaction-scoped maintenance authorization into the existing authenticated IPC request path. It does **not** release filesystem recovery mutations.

## Authorization flow

1. The App may request maintenance inspection without mutation confirmation.
2. A reconciliation request must include a non-zero Transaction ID and an explicit `operatorConfirmed` UI intent signal.
3. The request nonce must equal the enclosing IPC envelope `requestID`; the existing replay guard therefore protects the same identifier.
4. The Helper checks that the request timestamp is fresh and the session nonce matches the authenticated connection.
5. The authorization capability is minted only when the authenticated peer is unprivileged, the socket UID/GID/PID match the kernel-derived identity, the CDHash has the expected 40-hex format, the session nonce is well-formed, and complete Audit Token + PID Generation evidence is present.
6. The recovery capability is bound to exactly one Transaction ID and request nonce and has a bounded lifetime.
7. The Helper process itself must still be root before the privileged recovery coordinator can mutate files.

The connected App identity is subject to the existing `HelperPeerTrustPolicy`, which checks the provisioned allowed client UID and CDHash set before the authenticated peer context is created.

## Important UI-confirmation limitation

`operatorConfirmed` is a client intent signal. A compromised client can forge a Boolean field; it is not cryptographic proof that a human tapped a button. The security boundary is the authenticated and provisioned App code identity, kernel socket credentials, Audit Token, PID Generation, transaction binding, short expiry, and replay protection. A future stronger user-presence requirement would need an OS-backed authorization primitive supported by the target jailbreak environment; P2-26 does not pretend such a primitive exists.

## IPC changes

`HelperMaintenanceRecoveryRequest` now carries optional `transactionID` and `operatorConfirmed` fields. Inspection remains compatible with omitted values. Reconciliation requires both. The response echoes the authorized Transaction ID so the App can reject a mismatched response.

`HelperDeploymentCoordinator.requestMaintenanceRecovery` now requires `userConfirmed == true` and a Transaction ID before sending a reconciliation request. It binds `requestNonce` to the envelope request ID and validates the echoed Transaction ID.

## Release gates

- Maintenance recovery mutation remains disabled in the dispatcher.
- Normal deployment execution remains disabled.
- Plugin association commit remains disabled.
- Startup recovery remains read-only.
- No files are changed by the P2-26 maintenance IPC path.

## Host validation performed

- P2-26 static audit: 15/15.
- P2-25 static audit updated for the new App-peer boundary: 18/18.
- P2-16 through P2-24 static audits: passed.
- Helper target Linux Swift typecheck: passed.
- Sources, HelperRuntime, and UnitTests Swift syntax parse: passed.
- P2-25 durable recovery smoke, updated to model an unprivileged App peer and root Helper process: passed.
- P2-26 maintenance IPC smoke: passed (inspection, explicit confirmation, Transaction ID echo, missing confirmation rejection, request nonce mismatch rejection, mutation gate remains closed).

## Not validated

This environment does not provide macOS/Xcode, an iOS SDK, or a RootHide device. Therefore no claim is made for Darwin SDK compilation, XCTest execution on Apple SDK, actual app CDHash provisioning, RootHide App-to-Helper maintenance IPC, or device filesystem recovery. Those remain mandatory before enabling recovery mutation.
