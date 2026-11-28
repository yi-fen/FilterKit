# P2-44-R12 Changelog

## Prepared activation boundary hardening

- The production-shaped `activate(... prepared:)` preflight now decodes the exact provisioning-envelope bytes again and rebinds JBROOT, Release ID, Generation, Helper CDHash, and Team ID to the activation release tuple.
- Revalidates the prepared Journal hash chain before reading staged/previous artifacts.
- Validates the expected digest inventory against the three canonical artifact paths and prepared release hashes.
- Rejects duplicate expected-digest paths explicitly rather than constructing a `Dictionary(uniqueKeysWithValues:)` that could trap on malformed input.
- Preserves the existing ordering: process lock and persistent root activation lock are acquired before the prepared-evidence preflight; staged/previous stores remain lock-free adapters called inside that boundary.
- Does not open production execution gates or wire the executor into HelperRuntime/launchd.

## Validation scope

- Adds `p244_r12_prepared_activation_boundary_audit.py` and `run_p244_r12_validation.sh`.
- R12 audit checks source-level invariants only. Existing R5/R8 Host tests are rerun through the R11 validation chain.
- A complete Host end-to-end invocation of `HelperTrustedInstallerCoordinator.prepare()` followed by `activate(... prepared:)` is **not** claimed in this phase. The current test harness does not yet instantiate the production coordinator, production durable Journal store, production signature checker, and authenticated observer as one executable scenario.
- Darwin/Xcode/Apple SDK, XCTest, launchd/XPC, RootHide/ElleKit device, and power-loss validation remain unavailable.
