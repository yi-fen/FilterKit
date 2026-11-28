# P2-44-R4 Validation Report

## Baseline

- Input archive: `FilterKit-P2-44-R3-Source.zip`
- Expected SHA-256: `951ee4323badc3bf44f4f4acfa968880517ee05d5992228ce3ae17d9e17cafb6`
- Baseline `unzip -t`: passed
- R3 archive and prior work directory were not modified.

## R4 validation

- Previous Release Host Smoke: 10/10 passed.
- Previous Release Static Audit: 25/25 passed.
- Covered successful three-file backup, read-back hashes, Journal completion, no overwrite, tamper detection, interrupted partial backup, Journal completion I/O failure, retained complete backup with pending Journal, and active-source mismatch rejection.

## Scope limitations

- Host smoke runs on Linux and uses narrow model shims for the store's dependencies. It executes the real descriptor-relative store implementation, SHA-256 implementation, and Mach-O metadata parser.
- This is not a complete iOS/Helper target typecheck or Xcode build.
- Darwin `flock` behavior, iOS sandbox/JBROOT behavior, XCTest, RootHide/ElleKit device behavior, and real power-loss/kernel-crash behavior were not tested.
- The trusted previous-release hash/CDHash/Team inventory is supplied by the caller; R4 does not yet wire retrieval/authentication of that baseline to the trusted provisioning store.
- No production transaction operator is connected. Helper installation, activation, service start, rollback, and all plugin mutation gates remain closed.
