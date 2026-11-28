# P2-44-R6 Validation Report

## R6 direct validation

- Active Pointer integration static audit: **21/21 passed**.
- R5 Active transaction regression audit: **29/29 passed**.
- Real Host transaction smoke (actual executor + pointer writer + SHA-256): **13/13 passed**.
  - Three Active artifacts committed and Durable Journal advanced.
  - Pointer schema v2 binds Transaction ID, Release ID, Generation and all three artifact hashes.
  - Pointer rename failure returns indeterminate and retains transaction evidence.
  - Crash after pointer commit retains transaction evidence.
  - Recovery repairs a tampered pointer after independently verifying Active bytes.
  - Existing staged evidence, authenticated observer, stopped-service, rollback and Journal failure cases remain covered.

## Prior-phase regression

- P2-44-R1 write-gate audit: 23/23.
- P2-44-R2 Durable Journal audit: 20/20; Host smoke: 18/18.
- P2-44-R3 Staged Release audit: 26/26; Host smoke: 20/20.
- P2-44-R4 Previous Release audit: 25/25; Host smoke: 10/10.
- P2-43-R10 audit: 17/17; Host smoke passed.
- P2-43-R11 audit: 27/27; Host smoke: 17/17.
- P2-43-R12 audit: 25/25; Host smoke: 18/18.
- P2-43-R13 audit: 17/17; Host smoke: 13/13.
- P2-43-R14 audit: 20/20; Host smoke: 14/14.
- P2-43-R15 audit: 14/14; Host smoke: 15 assertions passed.
- P2-43-R16 audit: 14/14; Host smoke: 21 assertions passed.
- P2-43-R17 acceptance audit: 14/14.

## Repository validation

- Swift syntax parse: **285/285** source, test and Host-smoke Swift files passed.
- `Project.yml` YAML parse: passed.
- English localization: 519 keys, no duplicates.
- Simplified Chinese localization: 519 keys, no duplicates.
- Localization key parity: passed in the checked source baseline.
- All Build/scripts shell files passed `bash -n`.

## Important limitations / open integration item

- The R5 staged/previous `Inspection` values remain caller-supplied evidence objects. The existing R3/R4 stores expose disk inspection APIs, but R6 has not yet moved those reads into a single activation-lock-held adapter. This remains a production-blocking integration gap.
- This environment is Linux with Swift 6.2.1 and has no Xcode, Apple SDK, Darwin launchd/XPC, or RootHide/ElleKit device runtime. `xcodebuild` and XCTest cannot be run here.
- Darwin `flock`/`renameat` semantics, real power-loss/kernel-crash behavior, launchd behavior, and RootHide/ElleKit device acceptance remain unverified.
- No launchd bootstrap/start, HelperRuntime production wiring, or production mutation gate was enabled. Production write gates remain closed.
