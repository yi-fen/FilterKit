# P2-02 — RootHide ElleKit Filter Strategy Audit

## Baseline and source evidence

- Development baseline: P2-01, derived from P1-50.
- RootHide behavior reference: `roothide/ellekit` commit `16e3e7ed223c24c86ca2aaab6e78ad7d8d5c1d2e` (1.2-3), as documented in the uploaded R16.1 research bundle.
- Primary source locations cited by that research: `injector/injector.c`, especially `tweak_needinject` (approximately lines 83-358) and plugin enumeration/loading (approximately lines 366-438).
- Evidence type: static source review recorded in R16.1. It is not a new device validation and does not prove the user's installed ElleKit binary is the same revision.

## Confirmed 1.2-3 semantics from the supplied R16.1 research

1. Only `.dylib` files are enumerated. For `X.dylib`, ElleKit looks for the exactly same-basename `X.plist`; a missing or unreadable plist prevents injection.
2. RootHide runtime directory is `jbroot("/usr/lib/TweakInject/")`. `Library/MobileSubstrate/DynamicLibraries` is a compatibility symlink and is also part of ElleKit's integrity check. FilterKit must not replace or remove it.
3. Root plist must contain a `Filter` dictionary. `Bundles`, `Classes`, and `Executables`, when present, must be arrays of strings; malformed recognized fields cause the plugin to be skipped.
4. `Bundles`, `Classes`, and `Executables` are OR match dimensions. A hit in any one can select the plugin for the process. `CoreFoundationVersion` is a version gate, not an independent target selector.
5. A Bundle match requires a registered bundle and `CFBundleIsExecutableLoaded`; the comparison is case-sensitive in this fork.
6. A configuration change is read by a newly created process. Existing target processes do not reload their plugin list; the target App must be fully terminated and cold-launched for a fresh injection attempt.
7. On-disk configuration, an eligible filter match, and actual runtime load are separate facts.

## Consequence for per-App enable/disable

- Enable for one App can be represented as adding its exact Bundle ID to `Filter.Bundles`; this expands the OR set while preserving existing dimensions. The operation is not a runtime injection guarantee.
- Disable for one App is safe to preview only when `Classes` and `Executables` are absent or empty and the target Bundle ID is present. Removing the Bundle ID while either alternate OR dimension remains cannot guarantee the target App stops matching.
- A global/other match dimension must never be silently rewritten to force a per-App result.
- `CoreFoundationVersion` and unknown keys must be preserved byte-semantically where possible; this phase serializes an in-memory preview and never writes it.
- RootHide's documented filter shape is nested under top-level `Filter`. The planner fails closed on a missing/non-dictionary `Filter` instead of applying the generic root-dictionary fallback used by broader read-only parsing.

## Delivered in P2-02

Added `RootHideElleKitFilterStrategy.swift`, a pure in-memory planner for enable/disable previews. It validates RootHide's recognized field types, preserves unknown root/filter keys in the preview tree, and blocks a disable preview if `Classes` or `Executables` can still independently match.

Added unit tests for add, safe remove, alternate OR dimensions, already-associated state, malformed fields, missing Filter dictionary, and preservation of version/unknown keys.

## Deliberately not enabled

- No disk writes, Helper operation, file rename, `.disabled` marker, process kill, respring, global safe mode, or plugin binary replacement.
- `PluginActivationPreflightReport.mutationReleaseEnabled` remains `false`.
- `HelperRequestDispatcher.executionReleased`, `HelperDeploymentCoordinator.executionReleased`, and `HelperProductionDeploymentBackend.executionReleased` remain `false`.
- No third-party/package-manager plugin becomes writable.

## Remaining evidence required before a live toggle

1. Read the installed device's ElleKit package version and verify it corresponds to the reviewed RootHide 1.2-3 commit/profile.
2. Confirm exact on-device TweakInject path and compatibility symlink integrity.
3. On a FilterKit-owned test plugin, validate add/remove Bundle ID behavior for a plugin whose only match dimension is `Bundles`.
4. Validate that a plugin with `Classes` or `Executables` is blocked for per-App disable.
5. Cold-launch the target App and collect process-level load evidence; never infer injection from the plist preview.
6. Exercise backup, atomic replace, readback, crash recovery, and rollback only after the preceding evidence is accepted.

## Validation performed in this environment

- Swift parser checks: performed on project Swift sources.
- Focused Foundation typecheck and executable smoke tests: performed on the new pure planner and test scenarios where host compatibility allows.
- Xcode/iOS SDK build and XCTest: unavailable in this Linux environment.
- RootHide device validation: not performed.
