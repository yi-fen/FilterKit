# P1-13 — Enable/Disable Strategy Research and Safe Capability Gate

## Goal

Prepare a safe, profile-specific enable/disable boundary without changing any deployed plugin files. P1-13 does not implement deployment writes.

## Source research findings

### RootHide / Dopamine

- The public `roothide/ellekit` repository is a fork of `tealbathingsuit/ellekit` and identifies itself as an injector/hooking library. Its repository overview documents the hook APIs and project components, but the public overview does not specify a per-plugin `.disabled` marker contract or a manager-facing per-App enable/disable operation.
- The public `roothide/Dopamine-roothide` repository identifies itself as the RootHide integration of Dopamine 3.x. Its top-level project description does not document a per-plugin disable marker contract.
- The upstream Dopamine source exposes a global “tweaks disabled” safe-mode marker at `basebin/.safe_mode`. This is a jailbreak-wide switch, not evidence for an individual plugin/App toggle, and FilterKit must not use it for per-plugin management.
- The RootHide ElleKit repository and the Dopamine integration must be inspected at the exact deployed commits and tested on a device before any per-plugin mutation strategy can be considered verified.

### Rootless

- The Rootless environment is kept separate. No Rootless-specific per-plugin enable/disable semantics are asserted by this phase.
- RootHide evidence is never reusable as Rootless evidence.

### `.disabled` marker and Filter.plist mutation

- No authoritative source evidence collected in this phase establishes that adding/removing a `.disabled` suffix is recognized by the target ElleKit loader.
- No authoritative source evidence collected in this phase establishes that removing a Bundle from `Filter.plist` is a safe reversible disable operation. The original plist may contain plugin-owned keys, multiple matching dimensions, or unknown semantics. Rewriting it risks destroying behavior or changing scope.
- Therefore neither mechanism is implemented or probed by mutating files. The existing read-only Filter parser remains an observation only; its parsed Bundles list is not proof that a plugin is enabled or loaded.

## Implemented boundary

- `PluginDeploymentStateSnapshot` separates desired state, deployed configuration observation, and runtime observation.
- Configuration state never implies runtime loaded state.
- `EnableDisableStrategyResolver` returns `unverified` by default. It requires matching environment evidence, source revision verification, both enable and disable semantics, preservation of original plist semantics, and device validation before returning a mutation-capable strategy.
- RootHide and Rootless evidence cannot cross-resolve.
- `PluginToggleAuthorization` denies hard-bound App toggles, non-FilterKit ownership, permission failures, unavailable Apps, and unverified strategies.
- No Helper write plan, marker writer, plist writer, or deployment mutation is enabled in P1-13.

## External source references

- RootHide ElleKit source repository: https://github.com/roothide/ellekit
- RootHide Dopamine integration: https://github.com/roothide/Dopamine-roothide
- Dopamine upstream source (global safe-mode marker): https://github.com/opa334/Dopamine/blob/3.x/Application/Dopamine/Jailbreak/DOJailbreaker.m
- ElleKit package metadata reference (version/package identity only; not enable/disable semantics): https://github.com/roothide/roothide.github.io/blob/main/Packages

## Explicit non-conclusions

P1-13 does not claim that `.disabled` works, that Filter.plist Bundle removal disables a plugin, that a disk-resident plugin is loaded, or that any write operation is safe. Exact RootHide and Rootless loader behavior remains unverified until source-level commit inspection and device validation are completed.
