# P1-39 — Darwin Filesystem Hardening & Fault Injection

## Delivered

P1-39 hardens the standalone P1-38 Root Helper activation primitive without connecting it to HelperRuntime or opening the release gate.

### Cross-process transaction exclusion

- Adds a persistent `.filterkit-root-activation.lock` inode in the private transaction root.
- Acquires `flock(LOCK_EX | LOCK_NB)` before either activation or recovery.
- Requires the lock inode to be a root:root regular file, single-linked, and exactly mode `0600`; symlinks and unexpected inode metadata fail closed.
- Keeps the lock file after a transaction. It is intentionally not unlinked, because unlinking a held lock inode can split the lock domain between processes.
- Returns a distinct `lockBusy` failure when another process owns the transaction lock.

### Filesystem input hardening

- Opens artifact and journal files with `O_NONBLOCK | O_NOFOLLOW`, preventing a substituted FIFO from hanging a privileged verifier.
- Requires regular files to have one hard link, root ownership, and the expected mode/metadata.
- Reads the bounded journal through its already-open descriptor instead of reopening `/dev/fd/<n>` through Foundation.
- Uses a unique temporary filename for each journal replacement, so an orphaned temporary file from a process crash does not permanently block the next journal write.
- Retains Darwin `renameatx_np(..., RENAME_EXCL)` for no-replace artifact moves and atomic journal replacement; Linux host tests use `renameat2`/`renameat` compatibility paths.

### Fault injection

Adds deterministic fault points after:

- the prepared journal write;
- the first staged file;
- the first preserved backup;
- the first activation rename;
- the first progress journal write;
- the committed journal write.

The dedicated smoke harness exercises activation-rename interruption and verifies recovery to the previous release. Existing P1-38 smoke coverage continues to exercise interruption after a later artifact, successful rollback, upgrade, and manual-intervention behavior for unknown bytes.

## Validation

`Build/Scripts/p1-39-darwin-hardening-smoke.swift` passed on the Linux host:

- persistent lock file created with mode `0600`;
- a second independently opened descriptor cannot acquire the held exclusive lock;
- injected interruption immediately after an activation rename recovers to the previous release;
- foreign destination conflict remains rejected;
- first install and upgrade retain expected hashes and modes;
- unknown post-crash bytes still require manual intervention.

Full Swift source parse, focused Linux typecheck of the activation dependency set, project configuration, architecture, localization, and ZIP checks are recorded in `TEST-REPORT-P1-39.md`.

## Explicitly not validated

This environment is Linux, not Darwin. No claim is made that `renameatx_np`, `flock`, APFS durability, or iOS sandbox/rootless path behavior has been runtime-tested on an Apple device. Xcode/iOS build, XCTest, RootHide/Rootless device testing, code-signature/CDHash verification, launchd bootstrap/bootout, and physical power-loss testing remain outstanding.

The executor remains standalone; `executionEnabled=false` is unchanged. No live jailbreak paths were touched.
