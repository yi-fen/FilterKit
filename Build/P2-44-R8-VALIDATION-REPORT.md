# P2-44-R8 Validation Report

## New R8 results

- Disk Evidence Host Smoke: **25/25 passed**.
- Disk Evidence Static Audit: **25/25 passed**.
- The Host smoke compiled the actual Staged and Previous store source files and exercised their real descriptor-relative readers against root-owned Linux filesystem fixtures.

## P2-44 regression

- R1 Write Gate Audit: 23/23 passed.
- R2 Durable Store Audit: 20/20; Host Smoke: 18/18 passed.
- R3 Staged Release Audit: 26/26; Host Smoke: 20/20 passed.
- R4 Previous Release Audit and Host Smoke: 10/10 passed.
- R5 Active Transaction Audit and Host Smoke: 29/29 audit, 13/13 smoke.
- R6 Active Pointer Audit: 21/21 passed.
- R7 Disk Evidence Audit: 25/25 passed.
- R8 Disk Evidence Audit: 25/25 passed.

## P2-43 regression

- R10–R17 historical static audits passed.
- R10 transaction smoke: passed.
- R11 crash-recovery smoke: 17/17 passed.
- R12 filesystem smoke: 18/18 passed.
- R13 recovery smoke: 13/13 passed.
- R14 preflight smoke: 14/14 passed.
- R15 security smoke: passed (all emitted assertions passed).
- R16 dry-run smoke: 21 assertions passed.
- R17 acceptance audit: 14/14 passed.

## Repository checks

- Swift syntax parse: **274/274** files passed.
- `Project.yml` YAML parse: passed.
- English localization: 519 unique keys.
- Simplified Chinese localization: 519 unique keys.
- Localization key parity: passed.
- R8 Shell script syntax and Python audit compilation: passed.

## Scope limitations

- Linux Swift 6.2.1 Host environment; no Xcode or Apple SDK.
- No full iOS / Helper target build and no XCTest execution.
- The R8 harness uses narrow shims for surrounding domain types and transaction lock; it does not prove Darwin `flock`, Darwin filesystem behavior, launchd/XPC, code-signing runtime, or RootHide / ElleKit device behavior.
- R8 validates the two disk readers independently. It is not a complete end-to-end execution of the production-shaped R7 activation entry point, R5 three-file Active transaction, and R6 Pointer together.
- No real power-loss or kernel-crash test was performed.

**Conclusion:** R8 closes the immediate gap of having no executable Host tests for the R7 Staged / Previous disk readers. It does not authorize production activation. All production write gates remain closed.
