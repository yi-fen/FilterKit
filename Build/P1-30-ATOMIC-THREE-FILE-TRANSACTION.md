# P1-30 — Atomic Three-File Deployment Transaction

## Scope

P1-30 closes the P1-29 consistency gap by introducing one Helper-side transaction for the deployed dylib, matching Filter.plist, and Root-owned Schema 3 `.fk.json` manifest. First install and update use the same transaction engine but have different preconditions.

## Implementation

- `HelperThreeFileTransactionExecutor.swift` implements a root-only fd-relative transaction rooted at a fixed plugin directory.
- All path traversal uses directory file descriptors and `openat` with `O_NOFOLLOW`; public targets are exact leaf names derived from the matched dylib/plist pair.
- Staged payload bytes and the exact manifest bytes are held inside the Helper-side prepared deployment. They are re-hashed immediately before the transaction.
- The manifest is decoded as JSON and checked for Schema 3, matching Plugin UUID, exact dylib/plist names, payload SHA-256 values, hard-bound App identity, soft-association list and Mach-O identity fingerprint.
- The matching plist is parsed before mutation.
- The manifest is written as root:wheel mode `0600`; dylib and plist are root:wheel mode `0644`.
- A durable root-owned mode `0600` journal records transaction UUID, plugin UUID, exact three target leaves, new hashes, old hashes, phase, and deterministic temporary/backup leaf names.
- Journal replacement uses a temporary file, `fsync`, `renameat`, and directory `fsync`.
- First install requires all three targets absent. Update requires all three old files to exist and match the hashes re-read from the verified deployed state.
- All three old files are moved to transaction-specific backups before any new target is installed. New dylib, plist, and manifest are then renamed into place; the committed phase is persisted only after all three target hashes match and the directory is synced.
- Rollback restores all three old files, or removes all newly installed files for first install. A committed journal finalizes the new state and removes only verified backups.
- Any unexpected file type, owner, mode, hash, missing required backup, or mismatched destination returns manual-intervention/error and leaves the journal for inspection. There is no wildcard deletion.
- Recovery is idempotent. `inspectPendingJournal()` is read-only and is now included in `HelperStartupRecoveryCheck`; Runtime blocks service startup when the new journal is pending or invalid. Runtime does not automatically mutate files during startup.

## Pipeline preparation

`HelperAuthorizedDeployment` now carries Root-validated dylib bytes, plist bytes and exact Schema 3 manifest bytes inside the Helper process. The production backend builds a replacement manifest on update while preserving the original hard-bound App and soft associations, and rechecks package ownership before transaction entry.

`HelperProductionDeploymentBackend.execute(_:)` is connected to the three-file executor and produces a receipt including the manifest hash. The prepared update also carries the exact previous dylib, plist and manifest hashes captured during authorization; execution re-verifies those hashes and package ownership immediately before entering the transaction. A process-wide lock serializes transaction instances. The method remains protected by `executionReleased == false`, so it fails closed and is not currently capable of a real deployment. The Dispatcher and deployment manifest release gates also remain closed.

## Crash model

The transaction smoke injects process-loss points after each persisted phase:

- `prepared`
- `backingUp`
- `installingDylib`
- `installingPlist`
- `installingManifest`
- `committed`

For pre-commit phases, reconciliation restores the previous three-file state (or removes all partial files for first install). For `committed`, reconciliation retains the new three-file state and removes verified backups. Re-running reconciliation after cleanup reports no pending transaction.

## Safety boundaries

- No target App Bundle modification or re-signing.
- No dpkg command or dpkg database mutation.
- No arbitrary path supplied by IPC.
- No symlink traversal, shell execution, recursive deletion or wildcard cleanup.
- No plugin deletion feature.
- No real TweakInject write in this phase; Linux smoke writes only to a temporary test directory.
- This is filesystem transaction consistency, not a guarantee that ElleKit has loaded the plugin.

## Remaining validation

Darwin/iOS behavior for `openat`, `renameat`, `fsync`, ownership/mode semantics, and crash durability must be verified on the supported jailbreak/device combinations. Xcode/iOS SDK build, XCTest, Darwin compilation, launchd lifecycle validation, and RootHide/Rootless device testing have not been run in this environment.
