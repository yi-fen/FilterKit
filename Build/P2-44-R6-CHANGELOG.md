# P2-44-R6 — Active Release Pointer Production Update

## Scope

Integrate the existing Active Release Pointer writer into the existing R5 journal-bound three-file activation transaction. The pointer remains a non-authoritative hint; it cannot authorize or load a release by itself.

## Changes

- Extend the pointer to schema v2 and bind `transactionID`, `releaseIdentifier`, `generation`, and the exact SHA-256 hashes of the three Active artifacts.
- Publish the pointer only after the executor has replaced and read-back verified all three Active artifacts and advanced the Durable Journal to `activated`; it then independently reopens and re-hashes all three Active destinations immediately before pointer publication.
- Keep the R5 transaction record and Previous Release backups if pointer publication is indeterminate.
- Extend committed recovery to verify all Active artifact hashes, reconcile the Durable Journal, and idempotently republish the pointer before deleting transaction backups/evidence.
- Preserve descriptor-relative `openat`/`O_NOFOLLOW` traversal, exclusive 0600 temporary file creation, file `fsync`, atomic `renameat`, and parent-directory `fsync`.
- Require an existing pointer to be a root-owned regular file, single-link, mode 0600. A malformed or stale pointer is not trusted; successful recovery overwrites it only after Active hashes are verified.
- Add a pointer-publication fault injection point and Host smoke coverage for identity binding, evidence retention, and recovery repair.
- Update pointer schema fixtures in existing filesystem/recovery smoke sources and unit tests.

## Known boundaries

- The R5 staged/previous `Inspection` values remain caller-supplied evidence objects. Their source stores have read-only disk inspection APIs, but R6 has not yet moved those reads into a single activation-lock-held adapter. Production wiring must remain closed until this evidence boundary is resolved.
- The pointer writer uses the same root path and runs inside the existing activation executor lock; it does not reacquire the shared lock, avoiding nested flock on the same lock inode.
- No launchd bootstrap/start, HelperRuntime wiring, or production mutation gate was enabled.
