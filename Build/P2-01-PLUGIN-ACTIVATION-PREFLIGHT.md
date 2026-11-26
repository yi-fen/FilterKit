# P2-01 — Plugin Activation State & Read-Only Preflight

## Scope

P2-01 starts the activation/injection phase with a read-only decision model. It does not enable, disable, inject, install, replace, rename, or remove any plugin file. It does not change the Helper IPC protocol or release gates.

## Existing architecture audit

The P1-50 baseline already contains substantial groundwork:

- `PluginDeploymentStateSnapshot` separates user intent, on-disk configuration observation, and runtime observation. It explicitly reports injection success only for `.observedLoaded`.
- `EnableDisableStrategyResolver` defaults to `.unverified`; it requires environment-matched source revision evidence, both enable and disable semantics, preservation of original plist semantics, and device validation.
- `PluginToggleAuthorization` denies hard-bound App toggles, non-FilterKit ownership, insufficient management permission, unavailable Apps, and unverified strategies.
- `HelperRequestDispatcher.executionReleased`, `HelperDeploymentCoordinator.executionReleased`, and `HelperProductionDeploymentBackend.executionReleased` remain `false`. The dispatcher rejects operation requests and deployment batches before execution.
- `HelperThreeFileTransaction` is a deployment transaction for FilterKit-owned dylib/plist/manifest units. It is not an enable/disable mechanism and is not connected to released Helper execution.
- P1-13 research explicitly found no authoritative RootHide per-plugin `.disabled` marker contract and no safe, verified Filter.plist-removal contract. The global Dopamine safe-mode marker is not a per-plugin control and is not used.

## Delivered

Added `PluginActivationPreflight.swift`:

- Evaluates environment, ElleKit presence, FilterKit ownership, dylib/plist pairing, centralized management permission, hard-bound restrictions, target App availability, Bundle ID validity, strategy evidence, Helper reachability, and pending recovery state.
- Reports blockers as stable Codable values for later UI localization.
- Reports Filter.plist membership as a configuration observation only (`targetListed`, `targetNotListed`, `globalFilter`, `unavailable`).
- Always reports runtime state as `.notObserved`; a plist match or successful preflight is not proof of injection.
- Separates `inspectionOnly`, `blocked`, and future `readyForFutureMutation` disposition.
- Keeps `mutationReleaseEnabled = false`; even an all-green synthetic preflight cannot authorize a write in this release.

Added unit tests for unverified strategy, third-party ownership, config-vs-runtime distinction, hard-bound restriction, and unclean recovery.

## Safety boundary

- No mutation API was added.
- No new Helper operation was added.
- No `.disabled` suffix, Filter.plist rewrite, SpringBoard respring, process kill, or global safe-mode toggle is used.
- No third-party/package-manager plugin becomes manageable.
- The existing execution gates remain closed.

## Validation

- Swift parser validation: run across all project Swift files.
- Targeted model typecheck / smoke validation: run where host Foundation compatibility permits.
- Xcode/iOS SDK build and XCTest execution: not available in this Linux environment.
- RootHide ElleKit source revision semantics and on-device activation behavior: not yet verified. No activation method can be selected until exact source revision review and device tests establish reversible enable AND disable semantics.
