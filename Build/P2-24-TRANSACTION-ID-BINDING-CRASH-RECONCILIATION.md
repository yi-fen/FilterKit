# P2-24 — Transaction ID Binding & Crash Recovery Reconciliation

## Scope
P2-24 binds the durable deployment Batch Ledger to the three-file transaction journal. It does not release production deployment.

## Binding chain
- Dispatcher generates a Transaction ID only after the existing read-only/release gates pass.
- The durable Batch Ledger persists Batch ID, Batch SHA-256, operation Request IDs, Transaction ID, and state before the pipeline is entered.
- The pipeline derives an immutable `HelperDeploymentTransactionBinding` from the validated batch and Helper-authorized proof (plugin ID plus dylib/plist/manifest SHA-256 values).
- The production backend requires this binding and passes it to the three-file transaction executor.
- The three-file journal stores the binding alongside its own Transaction ID and expected artifact hashes before file staging/rename operations begin.
- The transaction receipt returns the same Transaction ID; the pipeline rejects a mismatched receipt.

## Recovery comparison
`HelperDeploymentJournalReconciliation` is a read-only policy. Startup compares ledger identity, transaction identity, operation IDs, ledger state versus journal phase, and all three expected artifact hashes against the actual destination files. It also validates backup files against old hashes and temporary files against new hashes. For an uncommitted journal, each destination must be absent or match its recorded old/new hash; a committed journal must match all three new hashes. Missing records or mismatches are hard failures (`ledgerMissing`, `transactionMissing`, `identityMismatch`, `artifactMismatch`). It never mutates files or authorizes rollback/commit.

## Compatibility
Three-file journal schema 1 remains readable. New deployment-bound journals use schema 2 and require the binding. Legacy schema-1 journals remain unbound and must not be treated as fully reconciled with a Batch Ledger.

## Safety boundaries
- Startup recovery remains inspection-only.
- Explicit recovery remains separately authorized and unreleased.
- Production execution and plugin-association commit gates remain `false`.
- No automatic cleanup, rollback, overwrite, or deletion was added.

## Validation limitations
Host-side source parsing, static audit, and focused policy tests do not establish Darwin/iOS SDK compatibility or RootHide device correctness. macOS/Xcode compilation, XCTest on Apple SDK, and RootHide device crash-injection tests remain required.
