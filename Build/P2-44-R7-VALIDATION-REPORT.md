# P2-44-R7 Validation Report

## Baseline integrity

- Input: `FilterKit-P2-44-R6-Source.zip`
- SHA-256: `6f7f0c9fc4ad0bc5b59e6e0cb7a0ab0747a58f30f4c98430ec61cdcb5232cdd7`
- `unzip -t`: passed before extraction.
- Work performed in a new `FilterKit-P2-44-R7-Work` directory; R6 archive/workspace was not overwritten.

## R7-specific validation

- `p244_r7_disk_evidence_audit.py`: 23/23.
- R6 Active Pointer static audit: 21/21.
- R5 Active transaction static audit: 29/29.
- R5 Host Active transaction smoke: 13/13. This executes the actual R5 executor/R6 Pointer writer with narrow Host shims; the Inspection-based overload is now deprecated and is used only by this legacy smoke.
- R4 Previous Release audit: 25/25; Host smoke: 10/10.
- R3 Staged Release audit: 26/26; Host smoke: 20/20.
- R2 Durable Journal audit: 20/20; Host smoke: 18/18.
- R1 write-gate audit: 23/23.
- P2-43 R10–R17 historical audits all passed; R10–R16 Host smokes passed (R17 is audit/acceptance only).
- All `Sources` and `Tests` Swift files passed `swiftc -frontend -parse`.
- `Project.yml` YAML parse passed.
- English localization: 519 unique keys; Simplified Chinese: 519 unique keys; no duplicates; key parity passed.

## What was not validated

- No complete Xcode/iOS/Helper build: `xcodebuild` and Apple SDK are unavailable in this Linux environment.
- XCTest was not run.
- The R7 new disk-evidence overload and the new staged/previous descriptor readers were syntax-parsed and statically audited, but were not exercised by a dedicated end-to-end root-owned store Host smoke fixture in this phase.
- Darwin `flock`, Darwin `renameat`, launchd/XPC behavior, real power-loss/kernel crash, and RootHide/ElleKit device acceptance were not tested.

## Release decision

**Production write gates remain closed.** R7 narrows the evidence trust boundary but does not authorize production activation. A later phase must add executable Host coverage for the new disk loaders/overload, wire only the disk-evidence API into the production adapter after review, and complete Apple-platform plus real-device acceptance.
