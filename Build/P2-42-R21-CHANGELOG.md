# P2-42-R21 — Helper Durable APP Activation Transaction Ledger

## Scope

R21 advances the R20 transaction record/query models into a Helper-side durable ledger and read-only IPC query path. The APP activation production write gate remains closed.

## Implemented

- Added `HelperAppPluginActivationTransactionLedgerStore` in the Helper execution layer.
  - Stores a bounded JSON ledger in the existing root-owned Helper directory.
  - Uses directory-descriptor-relative `openat` operations, `O_NOFOLLOW`, regular-file checks, root ownership checks, exact `0600` file mode, bounded reads, a unique temporary file, `fsync(file)`, atomic `renameat`, and `fsync(directory)`.
  - Corrupt, oversized, unsafe, or inaccessible ledger data fails closed; it is never treated as an empty ledger.
  - Duplicate command IDs and transaction IDs are rejected.
- Added restart handling: persisted `.executing` rows are durably changed to `.outcomeUnknown` before the Helper starts accepting IPC. No success/rollback inference is made from process restart.
- Integrated the ledger into the APP activation Commit path:
  - Persist `.executing` before starting the two-file Filter.plist/Manifest transaction.
  - Pass the same transaction ID into `HelperPluginFilterConfigurationTransaction`, binding the ledger row to the filesystem journal/receipt.
  - Persist `.committed` only after the transaction returns a receipt with matching transaction ID.
  - Any ambiguous transaction failure remains `.outcomeUnknown`; the code does not claim rollback without proof.
  - Existing duplicate command IDs cannot start a second transaction.
- Added `appPluginActivationTransactionQueryRequest` and `appPluginActivationTransactionStatusResponse` IPC message types.
- Added authenticated dispatcher routing and server request allow-list support for read-only transaction lookup.
- Added App-side `queryAppPluginActivationTransaction(...)` coordinator API. Each query gets a fresh transport request ID and is validated against the original command ID, Plugin ID, canonical Bundle ID, and response timestamp.
- Helper runtime opens the ledger from the existing root-owned Helper directory and marks interrupted executions unknown before wiring the dispatcher.

## Deliberately not implemented / not released

- No automatic conversion of `.outcomeUnknown` to `.committed` or `.rolledBack`. That requires matching filesystem-journal inspection and evidence-bound recovery authorization.
- No automatic retry of Commit.
- No UI affordance that retries or replays activation.
- No change to Helper identity/session/replay protections.
- No production activation Commit release. `activationCommitExecutionEnabled` remains false in production construction; the App-side Commit gate remains false.
- No association, uninstall, or deployment release gate changes.

## Important semantics

A ledger row left `.executing` after Helper restart becomes `.outcomeUnknown`. A repeated Commit with the same original command ID is rejected rather than executed again. A read-only query can report the persisted state, but `.outcomeUnknown` is not itself proof of either success or rollback.
