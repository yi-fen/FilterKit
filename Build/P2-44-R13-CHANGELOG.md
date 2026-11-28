# P2-44-R13 — Prepared Activation Host Integration

## Goal
Exercise the production-source `HelperTrustedInstallerCoordinator.prepare()` and `HelperRootAtomicActivationExecutor.activate(... prepared:)` path in one Host process, replacing the previous reliance on the legacy caller-supplied `Inspection` overload for the activation integration check.

## Added
- `Build/scripts/p244_r13_prepared_activation_smoke.swift`
  - Compiles and executes the actual `HelperTrustedInstallerCoordinator.swift`.
  - Compiles and executes the actual `HelperRootAtomicActivationExecutor.swift` and `HelperInstallerActiveReleasePointerWriter.swift`.
  - Uses a deterministic test-only signature checker and narrow Host dependency adapters.
  - Runs a file-backed temporary staged artifact set, creates a `HelperPreparedRootInstall` through `Coordinator.prepare()`, advances the Host Journal fixture to `staged + activateRelease intent`, and invokes the formal `activate(... prepared:)` overload.
  - Verifies invalid test signature rejection, stale Observer challenge rejection, staged-byte tamper rejection, successful Active activation, Journal state, Pointer metadata, and all three Pointer hashes against independently observed Active files.
- `Build/scripts/run_p244_r13_prepared_activation_smoke.sh`
- `Build/scripts/p244_r13_prepared_activation_audit.py`
- `Build/scripts/run_p244_r13_validation.sh`
- This changelog and the validation report.

## Scope / limitations
This is a meaningful Host integration test, but it is not a full production adapter test:
- The deterministic signature checker and provisioning signature verifier are Host-only test adapters; this is not Ed25519 verification.
- The Host staged-store adapter reads actual files in a temporary root-owned directory but is not the production R7 `HelperInstallerStagedReleaseStore` implementation and does not reproduce its full descriptor/ownership/link-count validation.
- The Host Durable Journal adapter is in-memory, not the production root-owned `HelperInstallerDurableJournalStore`.
- Observer identity is supplied through a test adapter; it is not OS-derived Darwin audit-token / code-signing identity.
- The test covers first-install activation. It does not yet execute the upgrade/repin Previous Release path or full crash Recovery through the prepared entry point.
- No production activation backend, launchd bootstrap, HelperRuntime wiring, or write Gate was enabled.
