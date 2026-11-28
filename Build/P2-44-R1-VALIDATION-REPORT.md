# P2-44-R1 Validation Report

## Baseline
- Input archive: `FilterKit-P2-43-R17-Source.zip`
- Expected and observed SHA-256: `f1f190ba3d121301f43602ff9838686b12b6f69aba6bb56862cfef7bc221ea73`
- Input archive integrity: `unzip -t` passed.
- Work was performed in a new P2-44-R1 workspace; R17 archive/workspace was not overwritten.

## Changes
- Added `P2-44-R1-WRITE-CAPABILITY-MATRIX.md`.
- Added machine-readable `P2-44-R1-WRITE-CAPABILITY-MATRIX.json`.
- Added `p244_r1_write_gate_audit.py`.
- No Swift production code or production write gate was changed.

## Executed validation
- Swift syntax parse: 273 Swift files passed, 0 failed (`swiftc -frontend -parse`).
- P2-44-R1 write-gate audit: 23/23 passed.
- Historical P2-43 R1–R17 Python audits: all passed.
- Historical P2-43 R10–R16 Host Smoke shell runners: all passed.
- `Project.yml` YAML parse: passed.
- English localization: 519 keys, 519 unique.
- Simplified Chinese localization: 519 keys, 519 unique.
- Localization key-set parity: passed.

## Limitations
- Environment: Linux Swift 6.2.1; no Xcode or Apple SDK.
- No complete iOS/Helper target build, XCTest, Darwin/launchd/XPC integration test, or RootHide/ElleKit device acceptance was performed.
- This phase is an inventory and audit-only release. No production write gate was opened.
