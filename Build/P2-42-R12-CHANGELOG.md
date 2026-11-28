# P2-42-R12 — Plugin page responsibility boundary and snapshot refresh

Baseline: `FilterKit-P2-42-R11-Source.zip`.

## Product responsibility (reaffirmed)

- The Plugins page manages only Additional App Association membership and plugin uninstall (uninstall remains locked by the existing production gate).
- The Plugins page does not enable or disable injection for any App.
- Per-App injection enable/disable remains exclusively in the Apps page.
- Plugin list/detail injection state is read-only status information; it is not an action control.
- Association checkmarks add/remove the relationship only. New relationships default disabled; removing/re-adding a prior relationship preserves its prior activation bit.
- The association edit model no longer exposes a per-App activation edit operation.

## Implementation

- Made `PluginsView` observe the existing `PluginScanRegistry.shared` directly so list scope, rows, and inventory count re-render from the current shared snapshot.
- Made plugin detail observe the same registry and resolve the latest matching plugin record by stable scan item ID, preventing stale detail content after refresh.
- Changed pull-to-refresh and explicit refresh actions to call the shared registry's `refresh()`; initial entry still uses `loadIfNeeded()` and does not start a duplicate scan.
- Kept App inventory name refresh on the existing shared App discovery notifications; no new scanner, cache, or polling loop was added.
- Clarified Chinese and English UI copy that the Plugins page only manages associations and does not control injection activation.

## Safety

- No production mutation gate was opened.
- Association commit remains governed by the existing Helper authorization and closed production release gates.
- Plugin uninstall remains disabled pending the existing real-device and transaction acceptance requirements.
- No injection, enable/disable, association topology, or ownership state is changed by this UI refresh work.
