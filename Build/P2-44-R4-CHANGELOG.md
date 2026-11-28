# P2-44-R4 — Previous Release Production Backup Qualification

## Scope

R4 adds a descriptor-relative, root-owned backup store for the currently active Helper release. It is transaction-scoped and only accepts `upgrade` / `repin` transactions with a durable `intentPreservePreviousRelease` Journal entry.

## New source

- `Sources/Environment/Helper/Runtime/HelperInstallerPreviousReleaseStore.swift`

## Storage contract

The pre-provisioned backup root is:

`<JBROOT>/Library/FilterKit/Helper/Recovery/PreviousReleases/`

Each backup is stored under the lowercase transaction UUID and contains exactly:

- `filterkit-helper` (`0755`)
- `Deployment.json` (`0600`)
- `cn.yfen.filterkit.helper.plist` (`0644`)

The directory must already exist as `root:root 0700`; R4 does not create/chown/chmod the production root. Existing transaction backup directories are never overwritten.

## Preservation flow

1. Require root effective UID and a clean JBROOT.
2. Require `upgrade` or `repin`, and a Journal whose durable pending operation is `preservePreviousRelease`.
3. Require a complete previous-release hash/byte-count inventory supplied by the trusted installed-baseline resolver.
4. Traverse active artifact parents using directory descriptors and `O_NOFOLLOW`.
5. Read only regular root-owned, single-link files with exact expected modes and bounded sizes; compare file identity before/after reads.
6. Match each active artifact against the supplied previous-release SHA-256 and byte count.
7. Verify the previous Helper Mach-O CDHash and Team ID, plus the disabled deployment/LaunchDaemon metadata contract.
8. Create a transaction-specific `0700` directory and write each artifact through a unique `O_EXCL|O_NOFOLLOW` temporary file.
9. `fsync` each file, atomically `renameat`, verify the written file by reading it back, and `fsync` the backup directory and its parent.
10. Only then advance the Journal with `preservePreviousRelease`.

If the final Journal save is indeterminate, the complete backup is retained and the method returns `journalCommitIndeterminate`. If a simulated process crash occurs during artifact writes, the partial directory remains for read-only inspection and the Journal intent remains pending.

## Read-only inspection

`inspect(transactionID:expected:)` reports `missing`, `complete`, `partial`, or `mismatched`, including missing/mismatched artifacts and unexpected directory entries. Inspection never repairs, deletes, overwrites, restores, activates, or launches anything.

## Security boundary

The `HelperRootReleaseSet.Verified` hash inventory and expected previous CDHash/Team ID must be obtained from the trusted installed-release baseline. The store checks the active bytes against those supplied values; it does not itself retrieve or authenticate the prior signed provisioning baseline. The production transaction adapter is not wired to this store in R4, and all global execution gates remain closed.
