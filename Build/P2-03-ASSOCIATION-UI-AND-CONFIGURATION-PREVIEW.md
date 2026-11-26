# P2-03 — Association UI & Configuration Preview

## Baseline

- Baseline: P2-02 RootHide ElleKit filter strategy audit.
- This stage adds a user-facing, read-only preview surface. It does not add a live toggle or file writer.
- The preview is limited to the RootHide environment because the planner models the RootHide ElleKit 1.2-3 filter semantics documented by the supplied R16.1 research bundle. The installed device revision is not verified by this UI.

## Delivered

1. Added an App selector to the plugin detail page for eligible FilterKit-owned plugins.
2. Added `Preview Enable` and `Preview Disable` actions that read the currently scanned plist path and call `RootHideElleKitFilterStrategy` in memory.
3. Shows planner disposition, blockers, Bundle IDs before/after, and unknown root/filter keys preserved by the planner.
4. Keeps hard-bound App immutable and excludes it from the target selector.
5. Blocks third-party, non-manageable, unpaired, unavailable-App, and unreadable-plist cases.
6. Displays explicit notices that the preview writes no files and is not evidence of injection/runtime loading.
7. Adds unit tests for preview eligibility policy: third-party denial, hard-bound immutability, and missing target/plist blockers.

## Safety boundary

- No file writes, renames, deletes, process termination, respring, or Helper requests were added.
- `PluginActivationPreflightReport.mutationReleaseEnabled` remains `false`.
- `HelperRequestDispatcher.executionReleased`, `HelperDeploymentCoordinator.executionReleased`, and `HelperProductionDeploymentBackend.executionReleased` remain `false`.
- No third-party/package-manager plugin becomes writable.
- No injection-success state is inferred from the preview.

## Important semantics

The preview uses the P2-02 RootHide filter planner. Bundles, Classes, and Executables are treated as OR match dimensions. Therefore:

- Adding a Bundle ID only previews the explicit Bundle entry; it does not prove ElleKit will load the dylib.
- Removing a Bundle ID is blocked when Classes or Executables remain populated, because those dimensions may still match the target.
- The preview is not a persisted desired-state store and does not update the deployed plist.

## Validation performed

- `swiftc -frontend -parse` across App, Sources, HelperRuntime, and Tests: passed.
- English and Simplified Chinese `.strings` syntax/duplicate-key scan: passed; no duplicate keys found.
- Focused typecheck of the pure preview policy and strategy using dependency interface stubs: passed.
- RootHide planner smoke checks (Bundle add preview and alternate-dimension disable block): 2 passed.
- XCTest source added but not executed in this Linux environment.
- Xcode/iOS SDK build: not executed; Xcode/iOS SDK unavailable.
- RootHide device validation and actual configuration write: not performed.
