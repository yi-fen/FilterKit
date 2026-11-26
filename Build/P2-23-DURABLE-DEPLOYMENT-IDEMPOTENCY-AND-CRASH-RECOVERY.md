# P2-23 — Durable Deployment Idempotency & Crash Recovery

## Scope

P2-23 replaces the deployment batch retry guard's process-only state with an optional, root-owned durable ledger and wires the production Helper runtime to it. The store is located beside the Helper's existing persistent manifest/audit state:

`<jbroot>/Library/FilterKit/Helper/.filterkit-deployment-ledger.json`

The store is a bounded (maximum 256 records / 256 KiB) JSON ledger, written through a unique `O_EXCL | O_NOFOLLOW` temporary file, `fsync`, atomic `renameat`, and directory `fsync`. Reads validate regular-file type, root:root ownership, mode 0600, size, schema decoding, digest shape, unique batch IDs, unique operation request IDs, and the configured root-owned non-group/world-writable directory. Corrupt, unsafe, or inaccessible state fails closed; it is never treated as an empty ledger.

## Recovery semantics

- `inProgress` persisted before execution is restored as `indeterminate` after Helper restart.
- `completed` remains completed and a matching batch cannot execute again.
- `indeterminate` remains blocked pending a separately authorized recovery decision.
- Reusing a batch ID with another digest/request-ID sequence is a conflict.
- Reusing an operation request ID in another batch is a conflict.
- Dispatcher now creates the ledger entry only after recovery/readiness/release-gate checks pass. It records `completed` after a successful pipeline receipt and `indeterminate` for any execution-path failure whose disk outcome may be uncertain.

## Important boundary

The durable batch ledger is now used by the production Helper runtime, but this phase does **not** yet persist a non-nil `transactionID` into the batch record or atomically co-commit the batch ledger with the file transaction journal. The record schema reserves `transactionID` for that next integration. Therefore, this is durable replay prevention and conservative crash classification, not a claim of end-to-end exactly-once execution. The existing transaction journal remains the authority for file-level recovery; any mismatch or pending transaction must continue to block deployment and require explicit recovery inspection.

No automatic rollback or file mutation was added to startup. All production execution/association release switches remain false.

## Validation

The unit test `testDurableLedgerRestoresInFlightAsIndeterminateAndCompletedAcrossRestart` covers restart classification using a temporary root-owned directory. Host-side syntax/typecheck and static gates are recorded in the P2-23 changelog. Darwin/Xcode and RootHide device behavior remain unverified unless separately run on target hardware.
