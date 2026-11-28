# P2-44-R7 — Locked Staged / Previous Disk Evidence

## Objective
Close the R5/R6 integration gap where activation accepted caller-supplied `StagedReleaseStore.Inspection` and `PreviousReleaseStore.Inspection` values rather than independently loading the exact staged and preserved bytes.

## Implemented

- Added `loadVerifiedArtifactsForActivation(transactionID:expectedHashes:)` to `HelperInstallerStagedReleaseStore`.
  - Opens the fixed staging root and transaction directory using descriptor-relative `openat` and `O_NOFOLLOW`.
  - Requires a root-owned private transaction directory and the exact three expected entries.
  - Reads all three artifacts from file descriptors; checks regular-file type, root ownership, single hard link, exact mode, bounded size, stable file identity/metadata, and SHA-256 against the trusted expected hashes.
  - Does not acquire another lock. It is intended to run inside the activation executor's already-held persistent transaction lock.
- Added the corresponding `loadVerifiedArtifactsForActivation` method to `HelperInstallerPreviousReleaseStore`.
  - Applies the same descriptor-relative, no-follow, exact-inventory, owner/mode/link, bounded-read, stable-identity, and hash checks to the preserved Previous Release.
  - Does not reacquire `HelperInstallerSharedTransactionLock`, avoiding nested `flock` on the same persistent lock inode.
- Added a disk-evidence activation overload to `HelperRootAtomicActivationExecutor`.
  - Accepts the coordinator-created `HelperPreparedRootInstall`, the actual Staged/Previous stores, and the trusted Previous Release inventory; it does not accept caller-created Inspection objects.
  - The evidence closure executes only after `acquireTransactionLock` succeeds and before the Active transaction record is written.
  - Reloads and compares the Durable Journal, binds transaction/action/release/generation, checks the authenticated stopped-service observation, loads staged bytes from disk, re-verifies them against the canonical release bundle/digests, and requires byte-for-byte equality with the release payload that will be activated.
  - Upgrade/repin requires a complete Previous Release inventory/store; disk bytes must match the expected Previous hashes and trusted byte counts. First install rejects unexpected Previous evidence.
- Marked the earlier Inspection-based activation overload deprecated and explicitly compatibility-only for the existing host smoke harness. Production integration should use the new disk-evidence overload.
- Kept R5 three-file activation, R6 Pointer publication, recovery, and all production write gates unchanged/closed.

## Security properties

- No second scanner/store or alternate activation executor was introduced.
- Staged and Previous evidence is read while the same persistent `.filterkit-root-activation.lock` is held by the activation executor.
- Store read methods intentionally do not nest the shared lock; stage/preserve writers already use that same lock on Darwin.
- The signed release verifier remains the source of target release integrity; disk hashes alone do not authorize a release.
- Pointer remains a non-authoritative hint and is published only by the existing R6 path after Active bytes and Durable Journal checks.

## Remaining limitations

- The new disk-evidence overload is implemented but is not yet wired into an enabled production installer adapter; the production gate remains closed.
- Previous Release identity metadata (release identifier/generation) is still supplied by the trusted Previous Release inventory object; the on-disk Previous directory contains the exact three artifacts, not a separate signed backup metadata envelope. The executor binds its hashes and byte counts to that trusted inventory.
- Host regression smoke continues to exercise the real R5 Active transaction and R6 Pointer code through narrow dependency shims. It does not execute the new R7 store-loading overload against a full root-owned Staged/Previous store fixture.
- Linux Swift 6.2.1 environment has no Xcode, Apple SDK, XCTest runner, Darwin filesystem semantics, launchd/XPC, or RootHide/ElleKit device. No complete iOS/Helper build or device acceptance is claimed.
