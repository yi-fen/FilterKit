# P1-24 — First-Install Authorization & Recovery Executor

## 1. Scope

P1-24 closes the isolated first-install bootstrap path and adds a hash-bound recovery action executor. It does not release production Helper operation dispatch.

## 2. Helper-side package ownership evidence

`HelperPackageOwnershipResolver` reads only explicitly configured dpkg `info/*.list` directories using fd-relative, no-follow operations:

- Requires root execution and root-owned, non-group/world-writable database directories.
- Reads only root-owned regular `.list` files with a 4 MiB per-file bound.
- Compares exact absolute paths for both the dylib and plist.
- Any exact package owner rejects the first-install request.
- An unreadable/unsafe database candidate rejects resolution; no available database yields `noDatabase` rather than an unowned result.
- A successful proof binds the exact plugin directory, exact two filenames, configured database directory set, a digest of scanned list evidence, and a short 30-second validity window.
- It never invokes dpkg and never modifies package-manager state.

The runtime profile has not yet been wired to supply the real RootHide/Rootless dpkg info-directory candidate set. The resolver is an isolated Helper API until that profile is verified on device.

## 3. First-install authorization and manifest bootstrap

`HelperFirstInstallManifestBootstrap`:

- Requires root execution.
- Requires an authenticated peer context whose kernel credentials match the identity evidence, a valid CDHash shape, non-empty session nonce, recent authentication time, and non-zero request ID.
- Validates exact dylib/plist names, hard-bound App ID, soft associations, plist parseability, and Mach-O identity fingerprint.
- Requires a fresh `HelperPackageOwnershipProof` bound to this exact plugin directory and filename pair.
- Requires both destination files to be absent before creating the authorization manifest.
- Creates `<basename>.fk.json` with `O_EXCL | O_NOFOLLOW`, root ownership, mode `0600`, file and directory `fsync`.
- A retry is accepted only when an existing root-owned Schema 3 manifest decodes to exactly the same manifest data. A different manifest is never overwritten.
- Returns a `HelperOwnershipProof` with `isFirstInstallAuthorization=true`; this proof is produced by the Helper bootstrap, not by App-supplied backup hashes.

`HelperSafeFileExecutor` now treats that proof as a first-install-only authorization and requires the destination plist to remain absent at execution time. Existing managed-plugin replacement still uses the separately verified ownership-proof path. This prevents a first install from taking over an existing unmanaged plist.

The intended isolated flow is:

1. Authenticate the peer and validate the exact import request.
2. Resolve package ownership from trusted Helper-configured dpkg info directories.
3. Create or idempotently recover the root-owned Schema 3 manifest authorization.
4. Execute the closed paired dylib/plist transaction using the returned proof.
5. Run `HelperOwnershipProofVerifier` against the deployed files.

This flow is implemented as isolated components and smoke-tested; the production IPC dispatcher does not call it yet.

## 4. Recovery action executor

`HelperTransactionRecoveryExecutor`:

- Requires root and a root-owned, non-group/world-writable target directory.
- Loads and validates the bounded root-owned transaction journal.
- Opens exact files with `openat(O_NOFOLLOW)` and validates regular-file type, root ownership, size bounds, and SHA-256.
- Obtains a deterministic action list from `HelperTransactionRecoveryPlanner`.
- Removes only exact journal-generated temporary/deployed leaves whose bytes match the journal.
- Restores the previous plist only after verifying its exact backup hash and confirming the destination is absent.
- Removes committed backup files only when their recorded hash matches.
- `fsync`s the directory after each action and clears only the fixed journal leaf.
- Returns `manualIntervention` for foreign bytes or inconsistent states; it does not guess or wildcard-delete.

The recovery executor is idempotent after a completed recovery: a second reconciliation sees no journal and returns `clean`.

## 5. Startup gate and remaining safety boundary

`HelperStartupRecoveryCheck` is wired into `HelperRuntime` before the socket server starts:

- No journal: Helper may continue to the existing health-only server.
- Valid pending journal: startup is blocked with `transactionRecoveryRequired`.
- Malformed/unsafe journal: startup is blocked with `invalidTransactionJournal`.

The startup path is deliberately read-only. It does not automatically execute recovery mutations against TweakInject until Darwin and RootHide/Rootless device validation is complete.

Unchanged release gates:

- `HelperDeploymentCoordinator.executionReleased == false`.
- Helper runtime rejects every `operationRequest`.
- Helper deployment manifest template keeps `executionEnabled == false`.
- `removeUnmanagedDylib` remains denied.
- No actual TweakInject write was performed by the runtime.

## 6. Validation

P1-24 validation performed in the Linux Swift environment:

- Full Swift parser check.
- Helper runtime/execution source subset typecheck.
- P1-22 paired deployment smoke regression.
- P1-23 ownership verifier smoke regression.
- P1-23 journal/recovery planner smoke regression.
- P1-24 root-side package ownership scan: unowned result accepted; exact dpkg owner rejected.
- First-install manifest creation, exact retry, first-install paired deployment, and subsequent ownership proof verification.
- First-install executor rejects an existing destination plist.
- Startup check detects a pending journal and returns clean after recovery.
- fd-relative rollback restores the exact previous plist, removes the transaction-created dylib/temp, clears the journal, and reaches clean state on the next check.
- Project identity/configuration, architecture, localization parity, and ZIP integrity checks.

Not run/not claimed: XcodeGen, Xcode/iOS SDK build, XCTest execution, Darwin/iOS compilation, launchd installation, actual RootHide/Rootless dpkg path discovery, real Helper IPC operation dispatch, automatic startup recovery mutation, or device TweakInject writes.
