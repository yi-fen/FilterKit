# P2-29 — App Scan Prewarm & DEB Profile Externalization

## Goal

Optimize the installed-App discovery path and the RootHide DEB packaging route
without changing the existing layering (Provider / ViewModel / View, and
script assemble-and-validate). The previous P2-28 baseline already shared one
cached discovery provider between the Apps and Plugins screens, removed the
container-directory walk on the successful LaunchServices fast path, read each
App's `Info.plist` once, trimmed the enumeration to `allInstalledApplications`
with an `allApplications` fallback, and deferred icon decode/private-API lookup
to row rendering.

This phase closes the remaining two gaps: launch-time warm-up of the inventory,
and packaging metadata externalization plus CI capability consistency.

## App discovery changes

### Background prewarm

- `CachedAppDiscoveryProvider.prewarm()` starts a detached scan that fills the
  in-memory cache. Failures are ignored; the next foreground
  `scanInstalledApps()` retries normally. The call never blocks startup.
- `MainTabView` triggers `AppDiscoveryProviderRegistry.shared.prewarm()` in a
  root-level `.task`, so the Apps/Plugins screens read a warm cache when they
  appear instead of blocking on the first LaunchServices enumeration.

### Deliberately not changed in this phase

- No two-stage "shell rows first, metadata later" rendering was introduced.
  The ViewModel still assigns the full inventory after the scan returns; a
  first cold launch before the prewarm completes still shows the loading state.
  A split-state model would touch the `InstalledApp` list contract and is left
  for a later, separately reviewed change.
- No in-flight task dedup was added to the actor. Concurrent first-entry scans
  could still overlap; the 60 s TTL cache already covers tab navigation.
- The LaunchServices enumeration shape is unchanged. The dual-bucket
  `enumerateApplicationsOfType:block:` path was already removed in an earlier
  phase; whether the remaining single-array enumeration covers every
  rootless/RootHide combination remains a device-coverage check.

## DEB packaging changes

### External RootHide profile

- New `Build/Config/DEB/roothide.env` holds package identity, manager-side
  architecture, rootfs payload layout, register path, dependencies, and
  control metadata. `package-deb.sh` sources this profile and only assembles,
  signs, validates, and archives the package.
- The script validates that required profile fields are non-empty, that the
  payload path ends in the declared bundle name, that the register path is the
  rootfs form of the payload path, and that the profile package id matches the
  App bundle id read from `Info.plist`.

### CI capability consistency

- The workflow form descriptions now state that DEB/Both packaging is supported
  for RootHide only; Rootless remains unverified.
- A pre-build workflow step rejects a `Rootless` matrix entry paired with
  `DEB`/`Both` before the build starts, with an explicit message to use
  `IPA`/`None` for Rootless. `ci-build.sh` keeps the same fail-closed check as
  a second line of defense.
- No Rootless DEB profile, payload layout, or conversion package is produced.
  The `/var/jb` prefix check in the RootHide package remains a forbidden-prefix
  assertion, not a supported layout.

## Changed files

| Directory | File | Change |
| --- | --- | --- |
| `Sources/Environment/` | `CachedAppDiscoveryProvider.swift` | Added `prewarm()` detached, failure-tolerant cache warm-up. |
| `App/` | `MainTabView.swift` | Root `.task` calls the shared provider `prewarm()`. |
| `Build/Config/DEB/` | `roothide.env` | New external RootHide package profile. |
| `Build/Scripts/` | `package-deb.sh` | Sources the profile; assembles control/postinst from profile variables; adds profile consistency assertions. |
| `Build/Scripts/` | `ci-build.sh` | Clarified the non-RootHide DEB rejection message and supported alternatives. |
| `.github/workflows/` | `build.yml` | Updated form descriptions; added package/environment compatibility pre-check. |

## Static validation (Linux host, no Xcode/iOS SDK)

- `bash -n` passes for `package-deb.sh` and `ci-build.sh`; the workflow YAML
  parses with PyYAML.
- The profile env sources cleanly; required fields are non-empty and the
  payload/register path assertions pass in an offline drill.
- Existing `CachedAppDiscoveryProvider(source:timeToLive:now:)` initializer and
  protocol methods are unchanged; `AppDiscoveryTests` still compiles against
  the same surface.
- No production write gate, plugin mutation, install, uninstall, or injection
  path was opened.

## Not run on this host

- Xcode build, XCTest on the Apple SDK, ldid signing, `lipo`/`otool` Mach-O
  checks, Sileo install, cold launch, and post-reboot launch. These remain
  Runner/device acceptance items. Static ldid validation still does not prove
  RootHide/amfid acceptance or runtime permissions.
