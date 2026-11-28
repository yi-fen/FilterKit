# P2-44-R2 — Durable Journal Production Write Qualification

## Scope

R2 hardens the existing `HelperInstallerDurableJournalStore` implementation. It does **not** enable Helper installation, activation, plugin deployment, plugin toggle, association, uninstall, or rollback execution gates.

## Changes

- Retains the pre-provisioned root-owned `0700` store directory contract; the store does not create, chown, or chmod production directories.
- Walks the absolute path through directory descriptors using `openat` and `O_NOFOLLOW`.
- Checks every ancestor: no group/world writable directories; a non-root-owned ancestor must not be owner-writable. The final store directory must be root:root `0700`.
- Creates journal temp files with `O_CREAT | O_EXCL | O_NOFOLLOW`, mode `0600`, then writes completely, `fsync`s the file, verifies root ownership / root group / regular file / single link / exact mode, and atomically renames relative to the verified directory descriptor.
- `fsync`s the containing directory after rename.
- Validates an existing journal before replacement. A replacement must preserve immutable transaction header fields and the complete existing entry prefix; stale sequence rollback and same-sequence forks are rejected. Exact same-head persistence is idempotently accepted, supporting retry after an uncertain directory sync.
- Journal reads validate root ownership, root group, regular-file type, single hard link, exact `0600` mode, bounded size, transaction identity, hash chain, and stable descriptor metadata before/after reading.
- Existing corrupt or unsafe journal files are not silently overwritten.

## Validation

- `p244_r2_durable_store_smoke.swift`: 18/18 Host checks.
- `p244_r2_durable_store_audit.py`: 20/20 static checks.
- Regression scripts: P2-44-R1 audit and P2-43-R10 through R17 smoke/audit suites.
- Swift syntax parse across repository Swift sources and tests.
- Project YAML and localization parity.

## Explicit limitations

- This is host filesystem qualification on Linux, not Darwin/iOS/XPC/launchd validation.
- The production root-owned store directory must still be provisioned by the trusted installer; this store intentionally does not create or repair it.
- Callers must continue to hold the shared installer transaction lock across read/modify/save sequences. This store does not replace the shared lock.
- No real disk-full, power-loss, or kernel-crash injection was performed; oversized-read rejection and bounded read behavior were exercised.
- No production write gate is opened in R2.
