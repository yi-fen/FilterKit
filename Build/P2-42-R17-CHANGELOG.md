# P2-42-R17 — Bundle Identifier Canonicalization at Lifecycle Boundaries

Baseline: `FilterKit-P2-42-R16-Source.zip` (SHA-256 `d685f0496d9b8440fba33852c145e8007f2f3b36e53d8c46249d60f6fdcc06b9`).

## Scope

R17 hardens Bundle ID identity comparisons across the APP activation reader, Plugin association editing, Filter.plist planning, Helper authorization, ownership verification, and uninstall consistency checks.

## Changes

- Added `HelperBundleIdentifierKey` as the shared comparison-key implementation. It trims surrounding whitespace and lowercases only for identity comparison; persisted/displayed Bundle ID spelling is retained.
- `HelperAppPluginActivationStateReader` now resolves Fixed Owner and Additional App Association state case-insensitively and rejects case-variant duplicates or mismatched schema mirrors.
- `PluginBindingTopologyValidator` and `PluginBindingTopologyEditor` now detect case-variant duplicates, Fixed Owner collisions, and add/remove requests by canonical identity.
- Helper mutation request validation and Plugin-page association policy reject case-variant duplicate associations and Fixed Owner collisions.
- `RootHideElleKitFilterStrategy` recognizes Bundle targets without case sensitivity. Duplicate Bundle entries that differ only by case fail closed with `duplicateBundleIdentifiers` instead of being silently accepted.
- `HelperPluginAssociationFilterMutationPlanner` compares manifest and Filter.plist target sets canonically while preserving original Bundle ID spelling in its public result fields.
- Helper mutation authorization, ownership proof verification, uninstall authorization, and two-file transaction consistency checks now compare binding identities canonically.
- Added regression coverage for mixed-case owner/association reads, case-variant duplicates, topology editing, and Filter.plist target planning.

## Product boundaries preserved

- APP remains the only page that performs first injection and per-App enable/disable.
- First injection remains enabled by default.
- Plugin remains limited to managing Additional App Associations and plugin uninstall; it does not change per-App activation bits.
- Adding an Additional App Association remains disabled by default.
- Fixed Owner remains immutable.
- No scanner, inventory cache, polling loop, or production write gate was added or opened.
