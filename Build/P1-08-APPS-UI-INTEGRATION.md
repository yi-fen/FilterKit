# P1-08 — Apps UI Integration

## Scope delivered

- Replaced the Apps tab placeholder with an installed-app inventory screen backed by `CachedAppDiscoveryProvider` and `LaunchServicesAppDiscoveryProvider`.
- Added name / Bundle ID search using the P1-07 inventory query.
- Added a toolbar filter menu with `All Apps` and `Apps with Plugins` modes.
- Added a persistent `Show System Apps` setting (`@AppStorage`, default `false`) in Settings.
- App visibility continues to follow the conservative P1-07 rule: when system apps are hidden, only apps positively classified as `user` are shown; `unknown` remains hidden.
- Added a read-only plugin scan + association projection to calculate the Bundle IDs that have verified FilterKit plugin associations. The association filter includes both hard-bound and currently effective soft-associated Apps. It does not alter associations.
- Added pull-to-refresh and an explicit refresh action; the existing 60-second in-memory cache remains in use for normal loads.
- Added an initial App detail information screen showing name, Bundle ID, classification, and discovered bundle path.
- Added matching Simplified Chinese and English localization strings.

## UI limitations intentionally retained

- App rows currently use a semantic SF Symbols icon (system / generic app), not the actual installed App icon. P1-07's `InstalledApp` model and LaunchServices adapter do not yet provide a validated icon-loading interface; no unsupported private icon selector was added speculatively.
- The App detail plugin section is a placeholder. Import, enable/disable controls, and actual per-plugin rows are later phases and are not implied to work in P1-08.
- App association status is derived only from verified FilterKit manifests. Package-manager and unknown plugins are not treated as FilterKit-managed associations.
- If plugin directory resolution or scanning is unavailable, the App inventory still loads; the associated-app filter safely returns no association matches.

## Safety boundaries

Read-only only. This phase does not modify app bundles, sign or re-sign apps, write plugin directories, rewrite manifests or plists, enable/disable plugins, or invoke dpkg.

## Validation

- Swift frontend parser across all project Swift files: PASS.
- Localization parity: PASS (97 keys in each locale; no missing keys).
- iOS deployment compatibility review: P1-08 UI avoids `LabeledContent` (iOS 16+) and retains the project's iOS 15 deployment target.
- Xcode / iOS SDK build: NOT RUN (Xcode unavailable in this environment).
- XCTest execution: NOT RUN (requires Xcode test runner).
- LaunchServices and real App icon behavior on Dopamine RootHide / Rootless: NOT RUN; requires device validation.
