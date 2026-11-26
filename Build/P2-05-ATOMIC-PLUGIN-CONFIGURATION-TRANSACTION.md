# P2-05 — Atomic Plugin Configuration Transaction

## Scope

P2-05 adds a dedicated Helper-side transaction for association edits. It replaces only the plugin's `Filter.plist` and FilterKit-owned `.fk.json` manifest. The dylib is never opened for writing, renamed, backed up, or removed by this transaction.

The executor accepts only a `PreparedMutation` produced by the P2-04 Helper authorizer. It rechecks the ownership proof, exact previous hashes, and exact previous bytes before staging. It validates the staged plist and schema-3 manifest, including plugin identity, paired filenames, and the manifest's new plist hash.

## Transaction protocol

1. Require root and a root-owned, non-group/world-writable plugin directory, traversed with `openat` and `O_NOFOLLOW`.
2. Reject an existing association journal.
3. Re-read both originals and require their hashes and bytes to match the P2-04 authorization snapshot.
4. Persist a transaction journal containing transaction/plugin IDs, exact leaf names, old/new hashes, and phase.
5. Stage both replacement files as exclusive root-owned files; `fsync` each and validate content/hash.
6. Copy both original files to transaction-specific root-owned backups; verify both backups and `fsync` the directory before replacing either destination.
7. Replace plist then manifest using directory-fd-relative `renameat`, updating and syncing the journal between phases.
8. Re-read both destinations and require both new hashes before marking committed.
9. Remove only transaction artifacts whose hashes match the journal, then clear the journal.

A crash before the committed phase is rolled back from the two verified backups. A committed journal is accepted only if both destinations still have the recorded new hashes. Unknown hashes, missing required backup evidence, malformed journals, and foreign transaction artifacts fail closed for manual intervention. Recovery is idempotent and explicit.

## Runtime integration

`HelperStartupRecoveryCheck` now performs a read-only probe of the association journal. A pending journal is exposed as `associationTransactionRecoveryRequired` and blocks normal mutation/deployment dispatch. No startup auto-repair is performed. The existing maintenance recovery action does not reconcile this journal; it remains a dedicated, unreleased recovery path.

The transaction executor is not connected to the IPC dispatcher. P2-04 prepare remains the only plugin-filter mutation IPC operation. No App confirmation UI or commit IPC is introduced here. All production execution gates remain closed.

## Validation

- Swift frontend parse across all `Sources` and `Tests`: passed.
- Focused Swift typecheck of the transaction, P2-04 authorizer, ownership proof/resolver, RootHide filter strategy, and dependent models: passed on Linux.
- Root-only Linux smoke test using a temporary directory: injected a crash after the first destination replacement, detected the pending journal, reconciled it, and verified both original files were restored byte-for-byte: passed.
- `Project.yml` YAML parse: passed; Helper target includes the complete `Sources/Environment/Helper/Execution` directory.
- XCTest suite not run.
- Xcode/iOS SDK build not run (Xcode unavailable in this environment).
- RootHide jailbreak-device validation not run.

This phase adds a tested transaction primitive, not a released or user-callable plugin toggle feature.
