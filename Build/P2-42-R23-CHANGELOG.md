# P2-42-R23 Changelog

## Goal

Separate read-only activation transaction status lookup from explicit, user-confirmed Helper reconciliation. Make journal cleanup retry-safe after the terminal Ledger state has been durably persisted.

## Changes

- Added `HelperAppPluginActivationTransactionReconciliationRequest` with a fresh transport request ID, original command ID, Plugin ID, Bundle ID, timestamp, and explicit confirmation flag.
- Added `appPluginActivationTransactionReconcileRequest` to the IPC message model and authenticated client request allow-list.
- Changed `appPluginActivationTransactionQueryRequest` to be strictly read-only: it reads the Ledger and returns status, without resolving `Outcome Unknown` or deleting transaction artifacts.
- Added an explicit Helper reconciliation route. It inspects the exact transaction Journal and current Filter.plist/Manifest hashes, resolves only a fully evidenced `Committed` or `Rolled Back` state, persists the terminal Ledger record first, and only then attempts Journal cleanup.
- Repeated reconciliation after a crash is idempotent at the recovery layer: a terminal Ledger row retries matching Journal cleanup only; it never replays Commit or replaces deployed plugin files.
- Added `finalizeResolvedActivationJournal`, which validates transaction identity, phase, both deployed hashes, backup hashes, and temporary-file hashes before deleting only that transaction's Journal artifacts. Unknown or mismatched evidence remains untouched.
- Added an APP-page-only “Verify with Helper” action for an unknown activation result. The action requires a confirmation dialog, disables the toggle while reconciling, and distinguishes Helper-confirmed commit from Helper-confirmed rollback. Plugin page responsibilities are unchanged.
- Added English and Simplified Chinese UI strings and tests for reconciliation request validation, IPC allow-listing, explicit coordinator reconciliation, and verified rollback Journal finalization.

## Safety properties

- No automatic Commit retry.
- No plugin file replacement or rollback in the reconciliation route.
- Read-only status lookup does not mutate the Ledger or Journal.
- Ledger terminal state is persisted before Journal cleanup.
- Cleanup is restricted to the matching transaction and exact expected hashes.
- The APP activation Commit release gate remains closed.
