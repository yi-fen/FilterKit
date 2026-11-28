# P2-44-R16 Changelog

## Goal

Connect the R15 real Store write path to the production-shaped `activate(... prepared:)` entry point and exercise a complete Host Upgrade plus Pointer recovery.

## Added

- `Build/scripts/p244_r16_full_upgrade_smoke.swift`
  - Calls the production `HelperTrustedInstallerCoordinator.prepare()`.
  - Uses production `HelperInstallerDurableJournalStore`, `HelperInstallerPreviousReleaseStore.preserve()`, and `HelperInstallerStagedReleaseStore.stage()` against a real root-owned Host filesystem fixture.
  - Persists `intentActivateRelease` and calls the production `HelperRootAtomicActivationExecutor.activate(... prepared:)` overload.
  - Compiles and executes the production Active Pointer writer and authenticated Observer validator.
  - Verifies all three Active files, the activated Durable Journal, and Pointer transaction/release/generation/hash bindings.
  - Injects a failure immediately before Pointer rename, then invokes production Recovery to republish the Pointer, finalize the committed Active set, and verifies a second recovery is idempotent.
  - Retains R15 Previous/Stage partial-write fault assertions.
- `Build/scripts/run_p244_r16_full_upgrade_smoke.sh`
- `Build/scripts/p244_r16_full_upgrade_audit.py`
- `Build/scripts/run_p244_r16_validation.sh`

## Production source changes

No production Swift source was modified in R16. This phase is an integration/acceptance harness that compiles and executes the existing production Coordinator, real Stores, Durable Journal Store, authenticated Observer validator, Active Pointer writer, and prepared Activation Executor together.

## Host-only adapters

The test uses deterministic signature and Mach-O metadata adapters, a Host peer-identity fixture, a simplified descriptor-observer adapter, and a no-op shared acceptance-lock adapter. The activation executor's own persistent root transaction lock (`flock`) and actual Active/Pointer filesystem operations execute on Linux. These adapters are not production implementations.

## Production gates

No production write gate, Helper deployment backend, launchd bootstrap, or HelperRuntime activation wiring was enabled.
