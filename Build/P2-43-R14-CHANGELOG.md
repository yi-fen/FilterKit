# P2-43-R14 Change Log

## Scope
R14 adds a second-pass recovery preflight contract. It connects the existing durable journal loader and descriptor-based filesystem observer behind a review-only inspection API, and adds explicit rollback/post-recovery validation. It does not add a recovery executor.

## Added
- `HelperInstallerRecoveryLayout`: active paths are sourced from the canonical `HelperRootReleaseSet` constants. Staged and previous roots must be explicitly supplied by the trusted installer integration under `Library/FilterKit/Helper/Recovery/`; traversal and overlapping roots are rejected. No production directory layout is inferred.
- `HelperInstallerServiceObservation`: a separate service observer must supply the exact launch daemon label, its pinned code-identity SHA-256, and either a stopped state or a running PID plus executable SHA-256. Unknown state and identity mismatch fail closed.
- `HelperInstallerRecoveryPreflight.inspect`: reloads the durable journal by transaction ID, re-observes active/staged/previous files through R12's descriptor-relative backend, then calls the R13 decision-only coordinator.
- Evidence fingerprint includes journal sequence/head hash, full observed file records (including device/inode/mode/owner), active pointer contents/match state, ownership result, and service observer identity/state. A second independently collected snapshot must compare equal before a review decision is considered fresh.
- Rollback prerequisite validator: only upgrade/repin journals in `rollbackRequired` with no pending operation, valid journal chain, exact complete previous-release hashes, authenticated service observer, and stopped service pass.
- Post-recovery validator: exact active artifact hashes, all three files present, ownership verified, pointer hashes and release identity/generation matched, authenticated observer, and service stopped are required.
- Host smoke and static audit; XCTest source added.

## Safety boundary and integration status
- This is an explicit integration contract, not proof that a production Root Installer currently supplies the stage/previous roots or a trusted service-observer implementation.
- `inspect` is read-only. It does not start/stop the service, write the pointer, replace files, roll back, or execute a recovery decision.
- The observer identity hash is a trust anchor supplied by a trusted caller; R14 does not implement code-signature verification for that observer.
- Second-pass equality detects changed evidence; it is not an acceptance lock and does not itself prevent TOCTOU. Any future executor must hold the shared installer lock and re-observe immediately before each side effect.
- No automatic recovery, rollback executor, LaunchDaemon observer, or production write gate is enabled.
