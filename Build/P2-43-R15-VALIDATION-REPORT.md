# P2-43-R15 Validation Report

## Baseline integrity

- Input: `FilterKit-P2-43-R14-Source.zip`
- SHA-256: `42c90c861b1f54b359ff137d3f27bf02cb4d27c8e60b416800e2a3b5af3c3beb`
- ZIP integrity: passed before extraction.
- Worktree: new `FilterKit-P2-43-R15-Work/FilterKit-P2-42`; R14 archive and prior worktree were not modified.

## R15-specific validation

- Authenticated observer + crash matrix Host Smoke: 16/16 passed.
- R15 Static Audit: 14/14 passed.

## Regression validation

- Swift syntax parse: 269/269 files passed (Swift 6.2.1 Linux).
- R10 transaction smoke: 11 assertions passed.
- R11 crash-recovery smoke: 17/17 passed.
- R12 filesystem smoke: 18/18 passed.
- R13 recovery smoke: 13/13 passed.
- R14 preflight smoke: 14/14 passed.
- R10–R15 static audits: all passed (R10 17, R11 27, R12 25, R13 17, R14 20, R15 14).
- Historical R1–R9 audits: all passed (12, 14, 14, 11, 13, 15, 10, 16, 18 assertions respectively).
- `Project.yml` YAML parse: passed.
- English and Simplified Chinese localization: 598 unique keys each; key sets identical.

## Environment limitations

- `xcodebuild` and Apple SDK are unavailable in this Linux environment.
- No complete iOS/Helper target build or XCTest run was performed.
- No Darwin `flock` runtime, launchd observer, XPC peer-authentication integration test, RootHide/ElleKit device test, or real power-loss/kernel-crash test was performed.
- Host smoke uses bounded test stubs for the authenticated observer contract. Static audit confirms lock-inode naming alignment; actual Darwin lock contention behavior remains to be verified on-device.
