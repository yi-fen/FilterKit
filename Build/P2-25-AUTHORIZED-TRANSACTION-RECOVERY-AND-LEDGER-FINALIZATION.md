# P2-25 — Authorized Transaction Recovery & Ledger Finalization

## Scope
P2-25 closes the recovery loop between the three-file transaction journal and the durable Batch Ledger. It does not register recovery as an ordinary IPC operation and does not release production deployment or plugin-association writes.

## Authorization boundary
`HelperRecoveryAuthorization` is minted only when all of the following hold:

- An explicit `operatorConfirmed` flag is true.
- The connected peer UID and authenticated identity UID are both root.
- Socket UID/GID/PID match the authenticated identity.
- The authenticated session is fresh and has a non-empty session nonce.
- PID Generation is present and non-zero.
- A 64-hex-character kernel Audit Token digest is present.
- The capability is bound to one non-zero Transaction ID and request nonce.
- The capability expires after the bounded authorization window.

This is deliberately a strict maintenance-only boundary. It is not a claim that the normal FilterKit app currently has a root-UID peer channel.

## Recovery protocol

1. Inspect the exact pending three-file journal.
2. Require the journal Transaction ID to equal the authorization Transaction ID.
3. Require a deployment binding and a matching durable ledger row.
4. Compare Batch ID, Batch digest, Transaction ID, Request IDs, plugin ID, expected artifact hashes, actual hashes, backup hashes, and temporary hashes.
5. Append `transaction_recovery_started` before filesystem mutation. If the audit append fails, abort recovery.
6. Reconcile by transaction ID while retaining the journal.
7. Persist the durable ledger terminal state (`completed` for a committed transaction, `rolledBack` for a pre-commit rollback).
8. Re-check destination hashes and require all backup/temp artifacts to be absent.
9. Clear the journal only after the ledger finalization has succeeded.
10. Re-run read-only startup inspection and require a clean result.
11. Append a best-effort completion audit event.

## Crash-window handling

The journal remains present between filesystem reconciliation and durable ledger finalization. If the Helper exits in this window, a later authorized recovery can re-run the same Transaction ID. If the ledger was already finalized but the journal was not cleared, finalization is idempotent and the journal remains the recovery marker until its final hash checks pass.

The `rolledBack` terminal state prevents the same Batch ID from being submitted again after a recovery rollback. It is not silently converted into a fresh attempt.

## Safety boundaries

- Startup remains inspection-only.
- Recovery requires an explicit transaction-scoped authorization capability.
- Recovery is not wired into normal app IPC dispatch.
- No automatic recovery is performed at Helper startup.
- Unknown hashes, identity mismatches, missing ledger rows, invalid authorization, or audit-start failure stop recovery.
- All production deployment and plugin-association gates remain `false`.

## Host validation performed

- P2-25 authorized recovery smoke: passed.
- Pre-commit injected crash -> rollback -> durable `rolledBack`: passed.
- Committed injected crash -> durable `completed`: passed.
- Simulated crash after ledger finalization but before journal removal -> idempotent recovery retry: passed.
- Wrong Transaction ID authorization: rejected.
- Explicit confirmation required: passed.
- Recovery audit start/completion records: passed.
- Focused Helper/Execution/Runtime Linux Swift typecheck: passed.
- Modified Swift source parse: passed.
- AF_UNIX nonce-bound Health smoke: passed.
- Untrusted CDHash rejection smoke: passed.
- Audit sink fsync/rotation smoke: passed.
- Static audits P2-16 through P2-25: passed.

## Not validated

This host environment does not provide Apple Xcode/iOS SDK or a RootHide device. Therefore no claim is made for Darwin SDK compilation, XCTest on Apple SDK, real RootHide root-peer maintenance authorization, device filesystem crash injection, or production plugin deployment. Those remain required before any release-gate change.
