# P2-44-R2 Validation Report

## Baseline

- P2-44-R1 archive SHA256: `d0cb6ce19dffa76ebf07bbc8503e54b9b7ead4fec2b79ccbd7ccef647544b696`
- Baseline ZIP integrity: passed.
- R1 archive and workspace were not modified.

## R2 results

- Durable Journal Host Smoke: 18/18.
- Durable Journal Static Audit: 20/20.
- Swift parser: 272/272 repository Swift source and test files parsed successfully.
- P2-44-R1 Write Gate Audit: 23/23.
- P2-43 R1–R17 static audits: all passed (R1 12, R2 14, R3 14, R4 11, R5 13, R6 15, R7 10, R8 16, R9 18, R10 17, R11 27, R12 25, R13 17, R14 20, R15 14, R16 14, R17 14).
- P2-43 R10–R16 Host Smoke regressions: all passed (R11 17/17, R12 18/18, R13 13/13, R14 14/14, R16 21/21; R10/R15 passed their existing smoke assertions).
- Project YAML parse: passed.
- English / Simplified Chinese localization key parity: passed.
- ZIP integrity: passed.

## Environment limits

Swift 6.2.1 on Linux. `xcodebuild` and Apple SDK are unavailable. No complete iOS/Helper target build, XCTest, Darwin runtime test, real RootHide/ElleKit device test, launchd integration test, or physical power-loss test is claimed.

## Write gate

All plugin / Helper production mutation gates remain closed. R2 qualifies only the durable journal persistence primitive.
