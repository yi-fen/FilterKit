# P2-42-R18 — Canonical Bundle Identity in App/Plugin State Projection

Baseline: `FilterKit-P2-42-R17-Source.zip` (SHA-256 `85cee52742183f1246fe2859740b092e59ef3ff03fcd32feb326786e0ebc35b3`).

## Scope

R18 carries the R17 Bundle ID comparison rule through the remaining App-facing activation and association read paths. It addresses case-only differences between the persisted Bundle ID spelling and the Bundle ID reported by the installed-app inventory.

## Changes

- `AppPluginActivationStateResolver` now matches Fixed Owner, Additional App Association, and Filter.plist Bundle targets by canonical Bundle ID. Soft-association manifest state is looked up using the same identity key.
- `PluginAssociationPlanResolver` now detects case-variant duplicate associations and Fixed Owner collisions, and resolves installed/missing App availability case-insensitively.
- `PluginAssociationPlanEditor` now adds, restores, and removes associations by canonical identity. It continues to create new associations disabled and preserves the prior enabled bit when restoring an existing association.
- `PluginActivationPreflight` and `PluginAssociationPreviewPolicy` now use canonical Bundle ID matching for Filter observations, installed-App availability, and Fixed Owner checks.
- `ReadOnlyPluginAssociationReader` now joins the single installed-App snapshot to persisted associations using canonical keys. It preserves the original Fixed Owner and missing-association spellings, uses the installed App's actual Bundle ID in the effective projection, and skips case-variant duplicate or owner-colliding association metadata rather than guessing.
- `PluginAssociationSnapshot.availability(for:)` now resolves Bundle IDs case-insensitively.
- Plugin association UI membership indicators, App availability labels, selection/removal, and review diffs now use canonical identity. No new scan, cache, or polling path was introduced.
- Added regression tests for mixed-case activation resolution, association editing, inventory joins, duplicate fail-closed behavior, preview eligibility, and preflight observation.

## Product boundaries preserved

- APP remains the only first-injection and per-App enable/disable entry point.
- Plugin remains the place for plugin management and Additional App Association membership only; it does not edit per-App enabled bits.
- New Additional App Associations remain disabled by default.
- Fixed Owner identity and original spelling remain unchanged.
- Existing Helper authorization, ownership verification, transaction recovery, replay protection, and production write gates were not weakened or bypassed.
- No production mutation gate was opened.
