# P1-49 — App Icon & Plugin Inventory Visibility Repair

## Baseline and source comparison
- Mainline baseline: P1-48 (itself based on P1-47.3).
- R16.1 `FKApplicationDiscoveryService` / `FastPluginInventoryEngine` and TrollFools 4.4-257 `AppListModel` / `App` / `EjectListModel` were inspected directly.
- R16 and TrollFools use LaunchServices for app enumeration. TrollFools resolves icons by bundle identifier through `UIImage._applicationIconImage(forBundleIdentifier:format:scale:)`.
- R16 fast plugin inventory enumerates every supported DynamicLibraries directory and records dylibs/plists without requiring DPKG ownership or FilterKit manifest verification.

## Root cause found in P1-48 UI
P1-48 deferred ownership/identity checks during the fast inventory, correctly leaving third-party plugins as `ownership == unknown` and `managementPermission.canModify == false`. However, `PluginsView.visiblePlugins` defaulted to `canModify == true` only. Consequently, the fast scanner could have discovered plugins while the default UI hid every unverified/package-owned entry. This is a visibility filter bug, not proof that the filesystem scan returned zero entries.

P1-49 changes the default scope to show the complete discovered inventory. The toolbar toggle now narrows the list to FilterKit-owned/identified entries. This does not grant write permission; management authorization remains unchanged.

## App icon changes
- App discovery now reads each app's Info.plist once rather than separately for display name and metadata.
- Added a runtime-resolved UIKit icon lookup fallback by bundle identifier, modeled on TrollFools 4.4. Existing file and asset-catalog lookup remains first.
- The icon view invokes the fallback even when no plist-derived descriptor exists.

## RootHide path discovery
- Added the R16-style process-wide `jbroot()` symbol probe (`RTLD_DEFAULT`) ahead of the libroot dylib-path probe. The result still passes the existing structural root validation before use.
- Existing read-only and ambiguity checks remain in place.

## Safety boundaries
- No plugin files or ElleKit configuration are modified.
- Unknown/package-owned plugins are visible but remain read-only.
- No DPKG, SHA-256, Mach-O, or manifest verification was reintroduced into the fast inventory.

## Validation
- Pending in this build environment: Xcode/iOS SDK compilation and XCTest execution.
- Required device checks: Chrome, QQ Browser, Dopamine-RootHide icons; app enumeration timing; plugin counts and scanned directory paths; verify that unknown/package-owned plugins appear in All Plugins while remaining non-manageable.
- Static source and archive checks are recorded in the delivery report.
