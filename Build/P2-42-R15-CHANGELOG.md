# P2-42-R15 — Lifecycle consistency and post-commit inventory refresh

## Scope

R15 continues from the verified R14 source archive. It focuses on consistency across the Plugin-page association editor, the canonical binding topology, the Helper's Filter.plist mutation planner, and the shared plugin inventory.

## Changes

- Added `PluginLifecycleEndToEndConsistencyTests` to exercise the domain topology editor and Helper Filter.plist planner as one lifecycle flow.
- Covered removal of an enabled Additional App Association: the removed Bundle target is removed from the proposed Filter.plist while Fixed Owner and retained App activation bits remain unchanged.
- Covered Plugin-page addition: a newly added Additional App Association remains disabled and does not enter the Bundle filter.
- Covered rejection of changing an existing association's activation bit through the Plugin-page mutation path.
- Covered removal while Fixed Owner is disabled, ensuring it is not silently re-enabled.
- After a validated Helper association-commit receipt, the Plugin page now refreshes the existing `PluginScanRegistry.shared` snapshot. The local draft is not treated as authoritative disk inventory before a valid receipt is returned.
- The refresh uses the existing single inventory registry; no second scanner, page-local cache, timer, or per-App activation control was introduced.

## Product boundaries retained

- APP page remains the only place for first injection and per-App enable/disable control.
- Plugin page manages Additional App Association membership and plugin uninstall only.
- Adding an association from Plugin page defaults to disabled.
- Removing an association removes its effective Bundle filter target in the Helper's proposed transaction; ambiguous alternate matching dimensions remain fail-closed.
- Fixed Owner identity and retained App activation bits are preserved.
- Plugin page may display activation state but does not edit it.

## Release safety

No production write gate was opened. Association commit and uninstall execution remain fail-closed pending signed Helper, IPC identity, transaction recovery, and RootHide/ElleKit device validation.
