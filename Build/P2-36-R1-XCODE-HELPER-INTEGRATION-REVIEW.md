# P2-36-R1 Xcode / Helper Integration Review

Date: 2026-11-27
Input: user-provided `FilterKit-P2-36-R1-Source.zip`

## Environment limitation

This review ran in a Linux x86_64 environment with Swift 6.2.1. `xcodebuild` and `xcodegen` are not installed, and an Apple iOS SDK is unavailable. Therefore an Xcode project generation/build, iOS target compilation, XCTest, signing, and device deployment cannot be performed here. Swift frontend parsing and a Helper-source semantic typecheck were used as the available checks; neither is represented as an Xcode build.

## Results

- ZIP integrity: PASS.
- P2-36-R1 static audit: PASS, 12/12 checks.
- Swift frontend parse of `Sources`, `App`, and `HelperRuntime`: PASS.
- Helper target source semantic typecheck on Linux (Swift 5 language mode): PASS with one compiler warning in `HelperPluginFilterMutationAuthorizer.swift` about a trailing closure in a guard expression. This is not an Xcode/iOS SDK build.
- Localization: `en` and `zh-Hans` each contain 382 entries, no duplicate keys; all 29 association-manager keys referenced by `PluginsView.swift` exist in both resources.
- Project manifest: source groups include the mutation models, Helper authorizer, transaction, dispatcher/runtime, app-facing commit service, and plugin UI through the configured source paths.

## Integration trace

1. `PluginsView.swift` mounts `PluginSoftAssociationManagerSection` in the plugin detail view.
2. The section's Save action calls `HelperPluginAssociationCommitService.replaceSoftAssociations(...)` after explicit confirmation.
3. The service builds an intent-only `HelperPluginFilterMutationRequest` with `.replaceSoftAssociations` and `desiredSoftAssociations`, plus optimistic hashes of the current plist and manifest.
4. `HelperDeploymentCoordinator.commitPluginAssociation(...)` serializes that request into `.pluginFilterMutationCommitRequest`.
5. `HelperRequestDispatcher` decodes and validates the request, checks recovery state and its independent release gate, then re-runs `HelperPluginFilterMutationAuthorizer.prepare(...)` at commit time.
6. If released and authorized, the dispatcher calls `HelperPluginFilterConfigurationTransaction.execute(...)`, which stages, journals, backs up, replaces and verifies the plist/manifest pair, with reconciliation on failure.
7. `HelperStartupRecoveryCheck` detects a pending association transaction journal and places the Helper in recovery-required state.

## Release boundary

Both independent gates remain `false`:

- `HelperDeploymentCoordinator.pluginAssociationCommitReleased`
- `HelperRequestDispatcher.pluginAssociationCommitReleased`

Consequently the end-to-end commit is intentionally not executable. The UI's save attempt fails closed; no real plugin configuration write should occur through this path.

## Remaining acceptance work

- Run XcodeGen (if used by the project) and `xcodebuild` on macOS with the supported Xcode/iOS SDK.
- Build both `FilterKit` and `FilterKitHelper` targets and run `FilterKitTests`.
- Resolve any SDK/compiler-specific diagnostics.
- On a RootHide/ElleKit test device, validate Helper IPC peer identity, request serialization compatibility, journal crash/reboot recovery, and filesystem ownership/mode behavior.
- Keep both release gates closed until those checks and explicit release approval are complete.

## Important scope note

The Host Smoke script in this archive performs the static audit and Swift syntax parse. It is not a runtime transaction fault-injection test. The semantic Helper typecheck above is an additional local check, not a substitute for device validation.
