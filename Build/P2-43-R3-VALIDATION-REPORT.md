# P2-43-R3 Validation Report

## Baseline

- Source baseline: `FilterKit-P2-43-R2-Source.zip`
- Verified SHA-256: `d6d8f93491df382a033a66c39e42accfe14589eb865e98d5848f3306214780bb`
- `unzip -t` passed before extraction.
- Development performed in a fresh `FilterKit-P2-43-R3-Work/FilterKit-P2-42` directory; R2 archive was not modified.

## Executed checks

- Swift frontend syntax parse: all Swift files under `Sources` and `Tests` parsed successfully.
- Targeted Swift executable compiled and ran the actual Bundle ID key, Manifest, Filter.plist parser, first-install binding policy, and Helper activation-state reader sources.
- Smoke assertions covered Schema 4 creation, Fixed Owner enabled by default, independent enabled/disabled associations, Filter.plist target mismatch rejection, canonical duplicate rejection, owner collision rejection, and activation-state reads.
- `Project.yml` YAML parse.
- English and Simplified Chinese localization key uniqueness and key-set parity.
- Source archive integrity and SHA-256 after packaging.

## Source tests added (not XCTest execution)

`PluginFirstInstallBindingPolicyTests.swift` adds five XCTest cases. They were syntax-parsed, but XCTest was not executed in this environment.

## Not executed

- Full iOS / Helper Xcode build: unavailable; this Linux environment has no `xcodebuild` or Apple SDK.
- XCTest execution.
- Darwin-specific Helper IPC / filesystem integration tests.
- Signed RootHide / ElleKit device acceptance.
- Real plugin injection, activation, association mutation, uninstall, or restore.

## Important remaining boundary

The IPC peer identity currently proves process credentials and CDHash, but does not itself carry a cryptographically verified App Bundle ID. R3 does not claim that the selected Fixed Owner Bundle ID is cryptographically bound to the IPC peer. That needs a separately designed and device-verified App identity attestation path before production Gate release.

All production write Gates remain closed.
