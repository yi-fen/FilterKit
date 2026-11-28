# P2-44-R14 Changelog

## Scope
R14 adds a Host integration smoke that compiles and executes the production implementations of:
- `HelperInstallerStagedReleaseStore`
- `HelperInstallerPreviousReleaseStore`
- `HelperInstallerDurableJournalStore`
- `HelperInstallerTransactionJournal`
- `SHA256Digest`

The test uses a root-owned fixture under `/root`, actual descriptor-relative file reads, real POSIX permissions, real SHA-256 checks, and the production durable Journal encoder/decoder and hash-chain reducer. Only narrow model/policy and cross-platform lock/Mach-O type shims are supplied by the Host harness.

## Covered
- Three-file Staged and Previous artifact reads.
- Upgrade Journal progression through previous-preserved, staged, and pending activation.
- Durable Journal save/load round-trip.
- Staged content tampering, expected-hash mismatch, and unexpected directory entry rejection.
- Previous symlink substitution and unsafe mode rejection.
- Durable Journal corruption rejection.

## Explicit limitations
- R14 does not run `HelperTrustedInstallerCoordinator.prepare()` or `activate(... prepared:)` in this harness.
- The Store read APIs are exercised directly against pre-created root-owned fixture directories; `stage()` and `preserve()` writers are not executed here.
- No real Mach-O identity, production Ed25519 signature, Darwin flock, XPC/launchd, Apple SDK, RootHide/ElleKit device, or power-loss test is performed.
- The lock shim is a no-op on Linux; this validates descriptor-relative store operations, not Darwin transaction-lock semantics.
- Production write gates remain closed.

## Validation entry point
`Build/scripts/run_p244_r14_validation.sh` runs the available P2-44 R1-R13 static audits, the R13 Prepared activation Host regression, the R14 real Store Host smoke, and the R14 static audit.
