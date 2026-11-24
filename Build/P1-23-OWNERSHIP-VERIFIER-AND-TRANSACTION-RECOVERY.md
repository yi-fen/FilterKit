# P1-23 — Ownership Proof Verification & Durable Transaction Recovery

## 1. Scope

P1-23 hardens the P1-22 paired deployment boundary. It adds an independent root-side verifier for an already deployed FilterKit plugin, a durable single-slot transaction journal, and a deterministic recovery planner. The executor now persists journal phases around its filesystem commit sequence.

The Helper runtime still rejects every `operationRequest`. `HelperDeploymentCoordinator.executionReleased` remains `false`; no production dispatch is enabled.

## 2. Ownership Proof Verifier

`HelperOwnershipProofVerifier` reconstructs a proof from disk rather than accepting proof fields from the App process:

- opens the configured plugin directory component-by-component with `openat(O_DIRECTORY | O_NOFOLLOW)`;
- requires the plugin directory to be root-owned, `root:wheel`, and not group/world writable;
- reads the exact `.fk.json` manifest as a root-owned `0600` regular file;
- requires FilterKit plugin manifest Schema 3;
- validates UUID, exact dylib/plist names, hard-bound App, soft association uniqueness and consistency;
- reads root-owned regular dylib/plist files without following symlinks;
- verifies both exact file SHA-256 values against the manifest;
- parses the deployed Mach-O bytes and independently recomputes the same install-name/UUID/CDHash/architecture fingerprint used by the inventory scanner;
- validates the plist as a property list;
- requires explicit package ownership evidence; only `verifiedUnowned` is accepted, while package-owned/conflicting and unavailable evidence are denied.

`HelperOwnershipProof` is now only returned after those checks pass when using this verifier. The existing proof initializer remains internal to the Helper module; runtime dispatch is not wired.

### First install / restore provenance remains blocked

This verifier intentionally cannot authorize a new plugin that has no pre-existing root-owned FilterKit manifest. A backup JSON, App-supplied hash, or staged payload is not proof of FilterKit ownership. P1-23 does not invent a trust bootstrap. A future first-install flow needs a separate root-side authorization record tied to the authenticated peer, validated backup payload, and exact install request before the root-owned manifest is created.

Package ownership must be independently resolved by the Helper before calling the verifier. The verifier requires an explicit `PackageOwnershipEvidence` value and accepts only `verifiedUnowned`; it does not invoke dpkg or infer package ownership from a path/name. The P1-23 paired executor still does not create or deploy the `.fk.json` ownership manifest, so this verifier currently covers only deployments for which a trusted root-owned Schema 3 manifest already exists.

## 3. Durable transaction journal

`HelperTransactionJournalStore` stores one bounded JSON journal at the fixed leaf `.filterkit-transaction.journal` inside the Helper-selected target directory:

- root-owned `0600` regular file;
- directory opened component-by-component with `O_NOFOLLOW`, root-owned and not group/world writable;
- bounded read and decode, schema validation, exact generated temporary/backup names;
- atomic temp-file write, `fsync(file)`, `renameat`, and `fsync(directory)`;
- refuses to replace a journal belonging to another transaction;
- `clear()` unlinks only the exact fixed journal leaf and fsyncs the directory.

The executor persists intent/phase before each rename boundary: `prepared`, `movingPreviousPlist`, `installingDylib`, `installingPlist`, and `committed`. It records the previous plist hash when replacing an existing plist. After a durable committed record, backup cleanup is best-effort; if cleanup or journal clearing cannot be confirmed, the committed journal is retained for later reconciliation.

## 4. Recovery planner

`HelperTransactionRecoveryPlanner` is a pure, deterministic planner. It requires a validated journal and verified hashes for every observed file. It returns only exact-leaf actions whose expected hash matches the transaction record:

- remove transaction-created temp files;
- remove a newly deployed dylib/plist only when its bytes match the journal;
- restore the previous plist only when the backup hash matches the recorded old plist hash;
- remove the previous backup after a fully committed transaction;
- clear the journal only after the required recovery actions;
- return `manualIntervention` for foreign bytes, malformed observations, or inconsistent states.

The planner does not enumerate arbitrary files, wildcard-delete, follow symlinks, or execute its own actions. The fd-relative recovery action executor and startup reconciliation loop are not yet connected. This is deliberate: P1-23 does not run an untested recovery mutation path against TweakInject.

## 5. Runtime and ownership gates

- `HelperDeploymentCoordinator.executionReleased == false` remains unchanged.
- Helper runtime still rejects every operation request.
- Helper deployment manifest template remains `executionEnabled == false`.
- `removeUnmanagedDylib` remains denied.
- First-install/restore authorization remains unresolved and blocked.
- No actual RootHide/Rootless TweakInject write was performed.

## 6. Validation

P1-23 validation includes:

- full Swift parser check;
- Helper execution/verifier/recovery subset Foundation/POSIX typecheck on Linux;
- synthetic Mach-O identity verification from root-owned manifest and deployed bytes;
- package ownership conflict denial;
- tampered dylib hash rejection;
- journal save/load/phase-update/clear smoke;
- interrupted-transaction rollback plan;
- committed-transaction backup cleanup plan;
- foreign transaction journal replacement rejection;
- P1-22 executor smoke rerun with journal integration;
- project configuration, architecture, and localization checks;
- ZIP integrity and SHA-256.

Not claimed: XcodeGen, Xcode/iOS SDK build, XCTest execution, Darwin/iOS compilation, real root Helper launch, RootHide/Rootless device validation, automatic recovery mutation, or production operation dispatch.
