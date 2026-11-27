# P2-37 — APP Detail Plugin Activation Manager

## Scope

P2-37 adds the App-scoped activation state model and App Detail switch-management surface. It does not enable production writes, call a Helper mutation operation, modify `Filter.plist` / manifest files, or claim runtime injection success.

## Implemented

- App Detail resolves plugins as hard-bound, soft-associated, or Filter-only matches.
- Each row is scoped to the current App bundle identifier.
- Hard-bound association remains immutable, while its activation preview is independently represented and is not blocked merely because it is hard-bound.
- Soft-associated state is cross-checked between schema-3 manifest `softAssociations[].isEnabled` and the target App's membership in `Filter.Bundles`.
- Hard-bound and Filter-only state is read from the parsed Filter configuration.
- Global `*` filters, non-valid Filter parses, alternate `Classes` / `Executables` match dimensions, missing soft manifest state, and manifest/Filter disagreement are shown as ambiguous/unavailable and lock the switch.
- Third-party and unknown ownership, unverified manifest/binary identity, invalid pairing, and unavailable target Apps fail closed.
- Switch interaction is a local preview only. The displayed configured state remains the read-only observation; the preview does not persist across reloads.
- Hard binding is an association invariant, not an activation invariant. The old hard-bound toggle-denial checks were removed from the activation preflight/authorization policy; the hard-bound compatibility enum cases remain defined but are no longer emitted.
- English and Simplified Chinese resources added.

## Current scanner limitation

The current `ReadOnlyPluginScanner` deliberately assigns `ownership = .unknown`, leaves `manifestIdentityBinding = .unverified`, and defers full manifest verification. Consequently, current scanned inventory will show the state and reason but will not expose an actionable preview switch until a trusted verification pipeline supplies FilterKit ownership, verified binary identity, and manageable permission. This is intentional fail-closed behavior; P2-37 does not invent ownership proof.

## Release safety

All release switches remain false:

- `HelperDeploymentCoordinator.pluginAssociationCommitReleased`
- `HelperRequestDispatcher.pluginAssociationCommitReleased`
- `PluginToggleReleaseGate.productionMutationReleased`
- `PluginActivationPreflightReport.mutationReleaseEnabled`

No App/Helper mutation call is added by P2-37.
