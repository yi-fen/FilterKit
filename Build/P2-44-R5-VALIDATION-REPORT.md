# P2-44-R5 Validation Report

## Baseline

- Input archive: `FilterKit-P2-44-R4-Source.zip`
- Expected SHA-256: `70210a2e4bf48fd794ba7efe9bdb55ef42af91e099bb51d9d13a97283105ed80`
- Baseline `unzip -t`: passed.
- Work performed in a new R5 workspace; R4 archive and prior workspace were not overwritten.

## R5 validation

- Active Three-File Host Smoke: 9/9 passed.
- Active Three-File Static Audit: 29/29 passed.
- The Host smoke executes the actual Active transaction implementation and SHA-256 source, with narrow test shims for release, Journal and authenticated observer contracts.

## Scope limitations

- No complete Xcode/iOS/Helper target build; Linux Swift toolchain only.
- XCTest not run.
- Darwin `flock`, Darwin rename semantics, launchd/XPC authentication, and RootHide/ElleKit device acceptance not tested.
- R3/R4 staged and previous inspections are caller-supplied evidence values; a unified locked byte-loading adapter directly from those stores is still outstanding.
- No production deployment backend is connected. All production release gates remain closed.
- No real power-loss/kernel-crash injection; fault injection is deterministic Host-level transaction interruption.
