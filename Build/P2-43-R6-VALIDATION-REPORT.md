# P2-43-R6 Validation Report

## Baseline

- Input: `FilterKit-P2-43-R5-Source.zip`
- SHA-256: `3d693062e7a8809acd136ca2b19452f70f4da2c4ea2f137f321aac2a6076cb6e`
- `unzip -t`: passed before extraction.
- Worktree: fresh `/mnt/data/FilterKit-P2-43-R6-Work/FilterKit-P2-42`; R5 archive was not modified.

## Actual source changes

- Fixed `DarwinPeerIdentityProvider.ownCDHash()` to read the Helper process's CDHash directly, rather than invoking the client-peer identity path without a socket audit token.
- Added `HelperClientCodeIdentityRotationPolicy`.
- Required a previous provisioning baseline for installer dry-run `.repin` and validated the exact identity continuity rules before producing the still-disabled plan.
- Added `HelperClientCodeIdentityRotationPolicyTests.swift`, host smoke harness, and static audit.

## Executed validation

- Swift syntax parse: 249/249 passed.
- R6 host smoke: 5/5 passed.
- R6 static audit: 15/15 passed.
- R5 identity audit: 13/13 passed.
- R1/R2/R3/R4 audits: 12/12, 14/14, 14/14, 11/11 passed.
- Project.yml YAML parse passed.
- Localization: 519 unique keys in each language; key sets match.

## Not executed

- No Xcode/iOS SDK build or XCTest run.
- No Darwin Security/csops/audit-token typecheck or runtime test.
- No signed App/Helper artifacts, installer execution, repin transaction, or persistent anti-rollback integration test.
- No RootHide/ElleKit device acceptance.

## Release posture

All production write and installer execution gates remain closed. R6 is source-level hardening plus host policy validation, not production authentication certification.
