# P2-35 — Plugin Soft Association Manager

## Product boundary

- The Plugins page manages plugin information and soft App associations only.
- It has no enable/disable controls and does not submit ElleKit activation changes.
- First-time `.dylib` / `.plist` import remains exclusively on the target App detail page.
- The Plugins page backup importer remains reserved for FilterKit backup data.
- Hard-bound App identity is displayed as immutable and is excluded from selectable soft-association Apps.
- Third-party, unknown, unpaired, identity-conflicted, or otherwise unauthorized plugins remain read-only.

## Implemented

- Added an App checklist to the FilterKit-managed plugin detail page.
- Selecting/deselecting installed Apps edits an in-memory `PluginAssociationPlan` draft.
- Existing schema-3 per-App activation bits are preserved; legacy schema-1/2 entries retain the existing compatibility interpretation.
- Newly added soft associations default to `isEnabled = false`. Creating a relationship does not activate injection.
- Missing/uninstalled soft-associated Bundle IDs remain visible and can be removed from the draft.
- Added a change preview listing additions/removals.
- The UI explicitly states that the draft is not saved. Helper association commit and production writes remain locked.

## Not implemented / not claimed

- No persistent association save in this phase.
- No Filter.plist or ownership Manifest mutation.
- No Helper IPC association commit.
- No plugin enable/disable switch on the Plugins page.
- No RootHide/ElleKit runtime change or device injection test.

## Safety

The following release gates remain false:

- `HelperDeploymentCoordinator.pluginAssociationCommitReleased`
- `HelperRequestDispatcher.pluginAssociationCommitReleased`
- All plugin execution and production mutation release gates.
