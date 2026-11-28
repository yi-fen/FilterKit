# P2-42-R24 Changelog

## Scope

R24 hardens the APP activation transaction lifecycle for App relaunch, concurrent Helper requests, and bounded Ledger storage. It does not release production activation writes.

## Changes

### 1. App relaunch recovery hint

- `AppPluginActivationOperationStore` now restores a structurally validated pending command hint from versioned `UserDefaults` storage.
- A restored hint always returns to `outcomeUnknown`; it is not treated as a Helper receipt or an enabled-state assertion.
- The hint is written only after Commit has been submitted and the result becomes uncertain (including invalid Commit proof).
- An old command is validated structurally without applying the short IPC freshness window. New transport query/reconciliation requests still receive fresh request IDs and timestamps.
- A scan-only observation can be dismissed visually, but cannot clear the unresolved command hint. Only a Helper-confirmed terminal state can clear it.

### 2. Cross-process Ledger serialization

- The activation Ledger now uses a stable, Root-owned `0600` lock file and `flock(LOCK_EX)` around every public read/modify/write operation.
- The lock is separate from the JSON Ledger because the Ledger itself is atomically replaced; locking that replaceable inode would not serialize writers after rename.
- Existing in-process `NSLock` protection remains in place.

### 3. Helper request serialization

- `HelperRequestDispatcher.dispatch` serializes request processing for the shared plugin-directory transaction Journal.
- This prevents two requests handled by the same Helper dispatcher from independently passing the recovery preflight and racing a single Journal.
- Read-only status requests remain read-only; reconciliation remains explicit and user-confirmed.

### 4. Capacity policy

- Ledger capacity exhaustion now reports `capacityReached` rather than conflating record-count exhaustion with byte-size overflow.
- No terminal history is silently pruned. When the record limit is reached, new activation transaction insertion fails closed and existing command/transaction IDs remain available for replay protection and reconciliation.
- Automatic archival/compaction is intentionally not introduced: moving records between separate files would require a separately journaled atomic migration protocol. R24 chooses bounded fail-closed retention rather than risking loss of deduplication history.

## Security posture

- APP remains the only activation/enable-disable entry point.
- Plugin management and association responsibilities are unchanged.
- Helper identity, ownership checks, journal evidence checks, and transaction hash checks are unchanged.
- Production activation Commit remains disabled.
