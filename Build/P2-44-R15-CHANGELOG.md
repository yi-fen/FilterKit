# P2-44-R15 — Real Store Write Integration

## Scope

R15 advances the R14 read-only Store Host coverage into real write-path coverage for the production Coordinator, Durable Journal Store, Previous Release Store, and Staged Release Store.

## Source changes

- Added `p244_r15_store_write_integration_smoke.swift`.
- Added `run_p244_r15_store_write_integration_smoke.sh`.
- Added `p244_r15_store_write_integration_audit.py`.
- Added `run_p244_r15_validation.sh`.
- Added this changelog and the R15 validation report.
- No production installer gate, launchd operation, or production Helper backend was enabled.

## Executed flow

1. The production `HelperTrustedInstallerCoordinator.prepare()` creates an immutable Prepared Upgrade using a deterministic Host-only signature checker.
2. The production Durable Journal reducer and disk Store persist each intent/completion transition.
3. The production Previous Release Store reads the three current Active files, checks them against the supplied trusted previous-release inventory, validates the previous executable identity and deployment/launchd metadata, then writes a transaction-scoped backup.
4. The production Staged Release Store verifies the prepared envelope/artifact binding and executable identity, then writes the three verified release artifacts into the root-owned Staged directory.
5. Both Stores are read back using their production descriptor-relative readers and checked against expected hashes.
6. The test confirms that Previous preservation did not mutate the current Active executable.
7. Fault injection after the first Previous artifact and after the first Staged artifact leaves partial evidence and the corresponding pending Journal intent; neither partial set is promoted to a completed state.

## Host-only substitutions

The smoke compiles the actual Coordinator, Journal reducer, Durable Journal Store, Staged Store, Previous Store, and SHA-256 source. Host shims are used for provisioning/signature models, release-set verification model, Mach-O metadata extraction, policy predicates, and the shared transaction lock. The deterministic signature checker and Mach-O metadata reader are test-only and are not production cryptographic or Apple code-signature validation.

Linux Host execution does not establish Darwin `flock` semantics. The supplied Previous Release inventory is a trusted-baseline fixture; this test does not integrate the trusted provisioning baseline loader. The smoke does not call `activate(... prepared:)`, does not replace Active files, does not update Active Pointer, and does not execute Recovery.
