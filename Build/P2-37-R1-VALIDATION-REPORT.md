# P2-37-R1 Validation Report

## Host results

- P2-37 static audit: **24/24 passed**.
- P2-37-R1 app-state audit: **15/15 passed**.
- P2-37-R1 activation model Host Smoke: **8/8 passed**.
- Swift parser over `Sources`, `App`, `HelperRuntime`, and `Tests/UnitTests`: passed.
- English and Simplified Chinese duplicate-key check: passed.
- XcodeGen `Project.yml` source discovery remains directory-group based; new source files are included by the existing `Sources` group.

Run:

```bash
Build/Host/run-p237r1-app-state-host-smoke.sh
```

## Coverage

- Hard-bound App may preview disabled state without changing the hard binding.
- Soft-association state is cross-checked against `Filter.Bundles`.
- Same plugin may report independent enabled/disabled states for separate Apps.
- Third-party and unknown ownership remain locked.
- Production-like scanner evidence (`ownership = unknown`, manifest binding unverified) remains locked.
- Identity collisions are rejected.
- Preview state is keyed by plugin plus target App.
- New scan revision clears all stale preview overrides.
- Static audit checks scan-generation protection against stale scan completions.

## Identity evidence boundary

This phase connects the existing scan/verification fields to a single fail-closed resolver. It does **not** claim that the current App scanner has begun producing trusted FilterKit ownership or Helper-attested identity evidence. The current scanner deliberately reports `ownership = unknown` and `manifestIdentityBinding = unverified`; therefore its real scan entries remain read-only. A future trusted Helper attestation/read-only verification response must be integrated before those entries can become eligible for preview or mutation.

## Not performed

- Xcode/iOS SDK build and XCTest Runner execution (requires macOS/Xcode).
- RootHide/ElleKit device validation.
- Signed Helper identity attestation or real device IPC verification.
- Filter.plist / Manifest mutation, Helper mutation, or injection.

## Release Gates

All remain `false`:

- `HelperDeploymentCoordinator.pluginAssociationCommitReleased`
- `HelperRequestDispatcher.pluginAssociationCommitReleased`
- `PluginToggleReleaseGate.productionMutationReleased`
- `PluginActivationPreflightReport.mutationReleaseEnabled`
