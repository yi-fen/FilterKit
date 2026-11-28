# P2-44-R14 Validation Report

## R14-specific results
- Real Store Host Smoke: 10/10 assertions passed.
- Real Store Static Audit: 24/24 checks passed.
- Production sources compiled and executed by the smoke: SHA256Digest, TransactionJournal, DurableJournalStore, StagedReleaseStore, PreviousReleaseStore.

## Regression
- R13 Prepared Activation Host Smoke: run separately; its Host shims remain in place and it is not counted as R14 real-store coverage.
- R1-R13 static audit scripts: run as a regression suite where available.

## Platform boundary
Host environment: Linux Swift. No Xcode/Apple SDK or Darwin runtime. No full iOS/Helper target build, XCTest, Darwin flock validation, production Ed25519, XPC/launchd, RootHide/ElleKit device acceptance, or physical power-loss test.

R14 verifies actual production Store read paths and durable Journal persistence against root-owned Linux fixtures. It does not claim a full end-to-end Prepared activation or production activation acceptance. Production write gates remain closed.

## Reproducible command
Run `Build/scripts/run_p244_r14_validation.sh` from any working directory; it resolves the repository root from the script path.
