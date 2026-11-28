# P2-45-R3 Validation Report

## Status

**HOST_FILESYSTEM_QUALIFIED / DARWIN_ROOTHide_RUNTIME_PENDING**

This is not approval to open production writes.

## Baseline integrity

- Input archive: `FilterKit-P2-45-R2-Source.zip`
- Input SHA-256: `45ebab56a53629d554d4a5239d38fc509cc182e589be19209c338514aeeebebf`
- Input `unzip -t`: passed
- R2 archive and workspace were not overwritten.

## R3 results

| Validation | Result |
|---|---:|
| Descriptor filesystem Host smoke | 24/24 |
| Filesystem / activation static audit | 24/24 |
| R2 identity / IPC static audit regression | 30/30 |
| R1 production gate static audit regression | 10/10 |
| R18 recovery Host regression | 80/80 |
| Swift syntax parse | 275/275 files |
| R1/R2/R3 shell syntax | passed |

The Host smoke ran as UID 0 in a private Linux directory tree. It exercised the production observer implementation, but the test root is not a real JBROOT and the host filesystem is not APFS.

## Filesystem controls observed

- Root path opened from `/` through directory descriptors.
- `O_NOFOLLOW` used for JBROOT components, nested directories, and leaf files.
- Relative paths reject absolute paths, dot traversal, empty components, backslashes, and NUL.
- Directory ownership and group/world write permissions are checked.
- Artifact files must be regular, expected-owner, single-link, non-group/world-writable, and within configured size limits.
- Reads verify stable device/inode/size/timestamps across the read.
- Only `ENOENT` is downgraded to an explicit missing state; unsafe type/permission/ownership conditions remain errors.
- Executor uses descriptor-relative operations, exclusive no-replace rename (`renameatx_np(..., RENAME_EXCL)` on Darwin), fsync, and a persistent root-owned flock lock.

## Important limitations

- No Darwin or APFS execution occurred.
- No RootHide JBROOT was inspected on-device.
- No iOS sandbox / jailbreak privilege transition was exercised.
- No RootHide ownership/group/mode contract was confirmed against a real device.
- No actual Darwin `renameatx_np`, APFS durability, power-loss, or kernel-crash behavior was tested.
- No launchd service stop/start or Helper deployment occurred.
- The R3 smoke compiles the production observer source up to the observer type boundary; the reconciliation adapter is covered by static review, not this isolated Host executable.
- The activation executor's Darwin branch is statically audited only. The Linux `renameat2` path is not a substitute for Darwin validation.

## Gate decision

Do not enable production writes. Required before R5:

1. Complete R1 on macOS with the actual App and Helper targets, Apple SDK, final signed artifacts, and signature/CDHash evidence.
2. Complete R2 on-device with actual Helper launch/deployment, kernel peer credentials, CDHash, signed identity, and IPC round-trip.
3. Run R3 on a RootHide device and capture JBROOT path, owner/group/mode, socket parent, all three artifact directories, no-follow behavior, no-replace rename, fsync and post-reboot recovery evidence.
4. Complete R4 end-to-end device acceptance, including interrupted transaction and reboot recovery.

Until then all production execution gates remain false/closed.
