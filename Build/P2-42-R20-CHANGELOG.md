# P2-42-R20

## Scope
Introduces the Helper-side APP activation transaction record and read-only query/status data contracts as the first implementation slice of transaction-result recovery.

## Changes
- Added `HelperAppPluginActivationTransactionRecord`, bound to the original activation command ID, plugin ID, target Bundle ID, desired state, transaction ID, and before/after Filter.plist + Manifest hashes.
- Added a constrained state reducer: `executing -> committed | rolledBack | outcomeUnknown`; an `outcomeUnknown` record may resolve to committed or rolledBack. Terminal states cannot be rewritten.
- Added query and status DTOs. Queries use a fresh transport request ID while retaining the original command ID, and responses are bound to plugin identity and case-insensitive Bundle ID identity.
- Added unit test source covering transition rules, Codable round-trip, query identity binding, and mismatch rejection.

## Explicit limitations
- This stage defines and validates the ledger schema/reducer and query contract. It does **not** yet add a root-owned durable on-disk store, dispatcher query route, Helper restart recovery integration, or App UI query flow. Those require the next implementation slice and device validation.
- No production write gate was changed. No activation or association mutation was executed.
