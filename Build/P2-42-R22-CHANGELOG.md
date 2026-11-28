# P2-42-R22 Changelog

## Goal

Bind APP activation `Outcome Unknown` resolution to the exact Helper association transaction journal and deployed file hashes. Recovery inspection is read-only with respect to plugin files; ambiguous or conflicting evidence remains `Outcome Unknown`.

## Changes

- `HelperPluginFilterConfigurationTransaction.execute` now accepts `retainJournalForOutcomeReconciliation` (default `false`). The APP activation commit path opts in, so the two-file journal survives the interval between file commit and durable activation-ledger finalization. Existing association-only callers retain their previous cleanup/reconciliation behavior.
- Added transaction-ID/plugin-ID/hash-bound `inspectActivationEvidence`. It validates the journal identity, old/new hashes, journal temporary file, backup hashes, temporary hashes, current destination hashes, and journal phase. It classifies only fully matching committed or previous-byte states; mixed, foreign, missing, or conflicting evidence remains unknown.
- Added `finalizeCommittedActivationJournal`, which clears a retained journal only after the activation ledger has durably recorded `Committed` and both deployed files still match the committed hashes.
- APP activation Commit now records `Committed` in the durable ledger before attempting journal cleanup. Cleanup failure leaves the journal for later inspection rather than invalidating the committed ledger record.
- The authenticated transaction-status query now inspects retained journal evidence for `Outcome Unknown`. It can resolve the ledger to `Committed` or `Rolled Back` only when transaction ID, plugin ID, Bundle ID, and both exact file hashes match the ledger row. The query does not replace, restore, unlink, or otherwise mutate plugin files. Invalid/missing evidence leaves the row unknown.
- `HelperAppPluginActivationTransactionLedgerStore.resolveUnknown` enforces the before/after hash pair again at the durable ledger boundary; callers cannot set a terminal state with arbitrary hashes.
- Corrected a pre-existing local binding in `HelperRequestDispatcher`'s plugin-filter prepare route: the returned `prepared` value is now retained before its response is encoded.
- Added XCTest source coverage for committed evidence, verified previous-byte evidence, mixed replacement state, foreign destination bytes, and ledger hash-bound terminal resolution.

## Safety boundaries

- No automatic rollback or recovery mutation was added to the status-query route.
- The journal remains present after a query resolves the ledger; existing recovery gates continue to block new mutations until the separate recovery workflow clears it.
- Missing journal evidence is not treated as proof of rollback.
- Production APP activation execution remains disabled in `HelperRuntime`; no production write gate was opened.
