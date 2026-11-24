# P1-45 — App Discovery & Plugin Inventory Reliability

## Scope

P1-45 starts from `FilterKit-NEW-P1-44-repair.zip` and keeps the existing Settings switch for showing system apps. No new system-app filter control is introduced on the Apps screen.

## Changes

### App discovery and classification

- LaunchServices enumeration now merges callback enumeration with both `allInstalledApplications` and `allApplications`, then deduplicates by bundle identifier. This avoids treating the two callback app-type buckets as a complete inventory when they are partial on a particular OS/jailbreak combination.
- Default app visibility now excludes only `.system` and `.hidden`; `.unknown` records remain visible. This prevents otherwise valid third-party apps from silently disappearing from the default inventory.
- A non-Apple app located under `/var/containers/Bundle/Application` is classified as a user app even if LaunchServices reports `applicationType == "System"`. This addresses TrollStore-installed IPA classification based on the app's actual container location.
- Icon descriptor parsing now reads nested `CFBundleIcons.CFBundlePrimaryIcon.CFBundleIconName` in addition to the legacy/top-level keys.
- The existing Settings > Show System Apps preference remains the single control for system-app visibility.

### Apps UI

- Replaced the filter menu and its redundant refresh action with one tap-to-toggle filter icon: All Apps ↔ Apps with Plugins.
- Kept pull-to-refresh on the list and retained retry actions in error/empty states.

### Plugin directory resolution

- Empty compatibility directories no longer compete with populated plugin directories.
- A sole populated directory is selected even when other recognized layouts exist but are empty.
- Multiple populated, distinct directories remain ambiguous; the locator does not guess between real inventories.
- If all recognized, accessible directories are empty, a deterministic layout preference is used and the scan can return an empty inventory instead of a false ambiguous state.
- ElleKit's component directory remains excluded from third-party plugin selection.

### Plugins UI

- Replaced the scope picker menu with one tap-to-toggle icon: FilterKit-manageable ↔ All Plugins.
- Moved import/export actions to the leading toolbar position and the scope toggle to trailing.
- Removed the redundant toolbar refresh action; pull-to-refresh and state-level retry actions remain.

## Tests added/updated

- Plugin directory: multiple empty directories, populated directory plus empty compatibility directory, and multiple populated directories.
- App inventory: unknown classification remains visible by default.
- TrollStore-style container app reported as `System` is classified as user; Apple system app remains system.
- Nested primary icon asset name parsing.

## Validation status

- Swift syntax parse: passed for all Swift files (`swiftc -frontend -parse`).
- Xcode/iOS SDK build and XCTest execution: not run in this Linux environment. Device verification is still required for LaunchServices private-API inventory completeness, icon rendering/permissions, and the expected installed-app count (the reported R16 count of 266 cannot be asserted without the target device).
