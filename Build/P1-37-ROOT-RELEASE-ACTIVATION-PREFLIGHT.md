# P1-37 — Root Release Set Verification and Recovery Preflight

## Scope delivered

P1-37 establishes a fixed three-artifact release contract for the future trusted Root Installer:

1. `usr/libexec/filterkit-helper`
2. `Library/FilterKit/Helper/Deployment.json`
3. `Library/LaunchDaemons/cn.yfen.filterkit.helper.plist`

`HelperRootReleaseSet` accepts exactly these relative paths, validates the executable size floor/ceiling, validates the disabled Root deployment manifest against the provisioned JBROOT/route, validates the launchd label/program path and requires `Disabled=true`, `RunAtLoad=false`, `KeepAlive=false`. All three staged bytes must match a complete SHA-256 inventory; missing, extra, duplicate or altered artifacts fail closed.

`HelperRootReleaseRecoveryAssessment` evaluates a snapshot of current destinations and transaction-specific backups against the expected new and previous hashes. It rejects unknown hashes, unproven ownership, malformed inventories, and missing previous artifacts. For known states it emits a read-only recommendation: resume pre-activation verification, restore the previous release, finalize only after re-verification, no-op, or manual intervention.

## Important boundary

This phase is the release-set verification and recovery-decision layer, **not** the filesystem activation executor. It does not create staging directories, preserve or rename files, change ownership/modes, write the durable journal, bootstrap/bootout launchd, or mutate a jailbreak. Recovery assessment consumes caller-supplied observations and never performs the recommended action. The existing `executionEnabled=false` and Root Installer release gates remain closed. No production activation path was added or connected to HelperRuntime.

The previous P1-30 plugin deployment transaction is a separate transaction domain and is not reused for Helper installation because its targets and trust contract differ.

## Validation still required

- Darwin/iOS compilation and XCTest.
- A dedicated fixed-path Root Installer adapter that safely spans the three destination parent directories, with durable journal ordering, backup ownership proofs, crash injection at every rename/fsync boundary, and idempotent recovery.
- Code-signature/CDHash verification and release provenance verification; SHA-256 here proves byte identity only.
- launchd lifecycle behavior and RootHide/Rootless device validation.
