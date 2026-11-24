# P1-36 — Durable Root Journal & Crash-Recovery Assessment

## Scope

P1-36 builds on P1-35's pure transaction state machine by adding a durable journal store and a read-only crash-recovery assessment. It does not add a privileged installer executable or any deployment/file activation adapter.

## Durable journal store

`HelperInstallerDurableJournalStore` operates only inside an already-existing directory whose path is absolute, contains no `.`/`..` components, and whose every path component is opened without following symlinks. The final directory must be a root-owned, root-group-owned directory with exact mode `0700`. The store does not create, chown or chmod it.

Saving a journal:

1. Validates the journal's complete event/hash chain.
2. Encodes bounded, sorted-key JSON.
3. Creates a unique temporary file using `openat(O_CREAT|O_EXCL|O_NOFOLLOW)` with mode `0600`.
4. Writes all bytes and fsyncs the file.
5. Verifies the opened file is regular, root-owned, root-group-owned and exactly `0600`.
6. Atomically renames the temporary file to the transaction UUID filename.
7. fsyncs the containing directory.

Loading opens the exact UUID filename with `O_NOFOLLOW`, checks regular-file type, root ownership, exact `0600` mode and size bounds, decodes the journal, checks its transaction ID and replays its hash chain.

The store provides atomic replacement and durability ordering for a single journal file. It does not provide a multi-process transaction lock, anti-rollback monotonic counter, authenticated MAC/signature, secure deletion, or cross-file atomicity. The existing SHA-256 chain is tamper-evident only against accidental/inconsistent edits; it is not keyed authentication.

## Recovery assessment

`HelperInstallerRecoveryAssessment` validates the journal before returning a state-based recommendation, including resume verification, preserve/restore prior release, verify activated release, finalize commit, confirm rollback, or manual intervention. It is deliberately read-only: it does not restore files, activate a release, start/stop launchd, or modify a manifest.

## Execution boundary

All P1-35 execution gates remain unchanged. `HelperInstallerTransactionPlan.executionEnabled` remains false. No root installer adapter exists, and the App cannot call this store to obtain elevated privileges. The store is a storage primitive for a future separately authenticated Root Installer process, not a privilege boundary by itself.

## Not implemented / not validated

- Privileged Root Installer binary, jailbreak package hook or authenticated IPC entry point.
- Signed release/provisioning envelope, trust-root rotation, Mach-O code-signature/CDHash verification.
- Inter-process journal locking, anti-rollback counter, authenticated journal MAC/signature.
- Multi-file activation transaction, fsync ordering across Helper/Manifest/launchd, rollback executor and reboot/crash integration tests.
- launchd bootstrap/bootout, socket directory lifecycle, ownership setup or actual install/uninstall.
- Xcode/iOS/Darwin build, XCTest execution, or RootHide/Rootless device testing.

No Helper was installed, replaced or removed. No launchd operation, TweakInject write, target App modification or re-signing was performed.
