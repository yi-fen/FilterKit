# P2-43-R4 Changelog

## Scope

R4 hardens the APP / Plugin responsibility boundary and completes another multi-App lifecycle consistency pass. The R3 source archive remains unchanged.

## Changes

### 1. APP activation can no longer create association topology

Added `HelperAppPluginActivationTargetPolicy` and integrated it into `HelperPluginFilterMutationAuthorizer`.

- APP activation requests may target the Fixed Owner or an already-recorded Additional App Association.
- Enabling an App that is not already associated is rejected by Helper authorization.
- APP activation cannot append a new Additional App Association.
- Plugin-page `replaceSoftAssociations` remains the only path that adds or removes Additional App Associations.
- Case-variant duplicates and Fixed Owner collisions fail closed.
- Activation updates preserve the Manifest's original Bundle ID spelling; request spelling is used only for identity comparison.

### 2. App inventory and App detail joins use canonical Bundle ID identity

Updated `AppsView.swift` so the shared association projection, associated-only list, App detail plugin membership, Fixed Owner grouping, Additional Association grouping, and filter-matched classification use `HelperBundleIdentifierKey`.

This avoids an App appearing unassociated solely because its Bundle ID spelling differs in case between LaunchServices and the plugin Manifest.

### 3. Regression coverage

Added `HelperAppPluginActivationTargetPolicyTests.swift` for:

- Fixed Owner case-insensitive matching.
- Existing Additional Association case-insensitive matching.
- Rejecting an unassociated target.
- Rejecting case-variant duplicate associations.
- Rejecting Fixed Owner / Additional Association collision.

Expanded `PluginLifecycleEndToEndConsistencyTests.swift` with a three-App scenario that confirms APP cannot invent a fourth relationship and Plugin association removal preserves other enabled/disabled targets.

Added `Build/scripts/p243_r4_app_plugin_boundary_audit.py`.
