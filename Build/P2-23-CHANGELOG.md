# P2-23 Changelog

## Durable deployment idempotency
- Added `HelperDeploymentDurableLedgerStore`, a bounded root-owned durable ledger using no-follow reads, 0600 records, atomic replacement, file fsync and directory fsync.
- Extended `HelperDeploymentIdempotencyLedger` to restore durable batch bindings. Persisted `inProgress` is treated as `indeterminate` after restart; completed batches remain blocked from replay.
- Wired `FilterKitHelperRuntime` to the durable ledger under `<jbroot>/Library/FilterKit/Helper`.
- Moved batch reservation until after recovery/readiness and execution-release checks, avoiding poisoning a batch ID while execution is disabled.
- Persisted `completed` only after a successful pipeline receipt; uncertain execution paths become `indeterminate`. Completion audit is best-effort and cannot downgrade a durable successful result.
- Added restart persistence XCTest coverage (skips when the test process cannot create a root-owned directory) and a host smoke test.

## Safety boundaries
- Durable ledger corruption, ownership/mode mismatch, capacity exhaustion, or I/O failure fails closed.
- No ledger eviction is performed: at 256 records the store refuses new batches rather than forgetting replay history. A separately authorized maintenance/compaction policy is still required.
- `transactionID` is reserved in the durable record schema but is currently nil; batch ledger and file transaction journal are not yet atomically co-committed. This phase is durable replay prevention and conservative crash classification, not end-to-end exactly-once.
- Startup remains inspection-only; no automatic file rollback/recovery was enabled.
- All production execution and association commit release switches remain false.

## Validation in this environment
- P2-23 static gate: 10/10.
- P2-22 compatibility static gate: rerun after updating its expectation for reservation-after-gate semantics.
- Swift frontend parse: all Sources, HelperRuntime and UnitTests files.
- Focused Linux typecheck: durable store + ledger using a minimal HelperPolicy stub (isolates the changed types; not a full target build).
- Durable restart smoke: inProgress -> indeterminate after reconstructed ledger; completed remains completed after another reconstruction.
- No Xcode/iOS SDK build, full XCTest, Darwin runtime, or RootHide device test was run.
