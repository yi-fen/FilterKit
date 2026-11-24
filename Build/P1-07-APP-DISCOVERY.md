# P1-07 — Installed App Discovery

## Scope

P1-07 introduces the installed-app discovery boundary for the jailbroken iOS runtime. It is read-only and does not modify application bundles, signing state, LaunchServices records, or jailbreak configuration.

## Runtime discovery

- `LaunchServicesAppDiscoveryProvider` resolves `LSApplicationWorkspace` dynamically and calls `defaultWorkspace` / `allInstalledApplications`.
- Each application proxy is read through supported Objective-C selectors (`applicationIdentifier`, `localizedName`, `itemName`, `bundleURL`, and `applicationType`).
- Invalid or missing Bundle IDs are skipped; duplicate Bundle IDs collapse to one record.
- `applicationType` values `System` and `User` map to explicit classifications. Any other or unavailable value remains `unknown`; the provider does not infer system status from filesystem paths.
- Display name falls back to Bundle ID when LaunchServices provides no name.
- Bundle URL is descriptive metadata only.

## Inventory model and filtering

- `InstalledApp` now carries `AppSystemClassification` (`system`, `user`, `unknown`).
- The existing `isSystemApp` convenience property remains available.
- `AppInventoryQuery` searches display name and Bundle ID using localized case-insensitive matching and returns stable name/Bundle ID ordering.
- With system apps hidden, only confirmed `user` apps are shown. `unknown` is deliberately withheld rather than accidentally exposing system apps; a future UI can expose an explicit unknown category.

## Cache

`CachedAppDiscoveryProvider` wraps any `AppDiscoveryProvider`:

- Default in-memory TTL: 60 seconds.
- Explicit `refreshInstalledApps()` bypasses the cache.
- `invalidateCache()` clears cached inventory.
- Results are deduplicated and sorted.
- `findApp` uses the same cached inventory.

No persistent cache is written in this phase.

## Boundaries and limitations

- LaunchServices is a private iOS API and availability/selector behavior must be validated on supported Dopamine devices.
- The provider is dynamically resolved and fails with a typed error if LaunchServices, workspace, or enumeration is unavailable.
- This phase does not wire the Apps UI or Settings' persistent “show system apps” preference; it supplies the discovery, filtering, and cache layer for that integration.
- No Xcode/iOS SDK build or jailbreak-device validation is claimed unless separately executed.
