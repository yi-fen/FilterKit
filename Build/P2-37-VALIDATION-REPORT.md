# P2-37 Validation Report

## Host validation

- Static audit: 18/18 passed.
- Activation model executable smoke: 4/4 passed.
- Swift parser over App, Sources, HelperRuntime, and UnitTests: passed.
- English and Simplified Chinese duplicate-key check: passed.
- Project source discovery uses directory groups, so the new model and test source are included by the existing XcodeGen configuration.

Run:

```bash
Build/Host/run-p237-activation-host-smoke.sh
```

## Unit tests added

`Tests/UnitTests/AppPluginActivationStateResolverTests.swift` covers:

- hard-bound App can be disabled without changing its immutable binding;
- soft manifest state and Filter.Bundles must agree;
- same plugin has independent state for two target Apps;
- third-party and unknown ownership never expose a toggle;
- global filters, alternate match dimensions, and missing manifest state are locked.

XCTest has not been run under Xcode in this Linux environment. No Apple SDK build or device validation is claimed.

## Safety

P2-37 toggles are preview-only. No production Filter write, manifest write, Helper mutation, or injection was enabled. Runtime state remains unobserved.
