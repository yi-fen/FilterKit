# P2-44-R3 Validation Report

## Executed checks

- `Build/scripts/run_p244_r3_staged_release_smoke.sh`: 20/20.
- `Build/scripts/p244_r3_staged_release_audit.py`: 26/26.
- Swift syntax parsing: 273/273 project Swift source and test files.
- P2-44 R1 Write Gate Audit: 23/23.
- P2-44 R2 Durable Journal Audit: 20/20; Durable Journal Host Smoke: 18/18.
- P2-43 R10-R17 static audits: all passed.
- P2-43 R11-R16 regression Host Smoke: 17/17, 18/18, 13/13, 14/14, pass, and 21/21 respectively; R10 transaction smoke also passed.
- `Project.yml` YAML parsing: passed.
- English and Simplified Chinese localization: 519 unique keys each, identical key sets.

The R3 Host smoke compiles the real `HelperInstallerStagedReleaseStore.swift`, `SHA256Digest.swift`, and `MachOMetadataReader.swift`, with minimal model shims for surrounding trusted preparation / Journal types. It exercises a synthetic signed Mach-O fixture and real Linux descriptor-relative filesystem writes under a root-owned test directory. The Linux smoke path intentionally does not claim to exercise the Darwin shared `flock` lock; the production Darwin branch calls the existing `HelperInstallerSharedTransactionLock`.

## Limitations

- No Xcode or Apple SDK is available in the Linux host environment.
- No complete iOS / Helper target build or XCTest execution is claimed.
- No Darwin `openat`/`fsync`/`renameat` runtime acceptance or RootHide device test was performed.
- No real power-loss or kernel-crash test was performed.
- The root-owned `StagedReleases` base directory must be provisioned separately and is not created by this stage.
- The new store is not wired into a production Root Installer adapter; production install/activation remains closed.
