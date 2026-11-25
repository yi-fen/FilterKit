# P1-46 — R16 Discovery & Inventory Restoration

## Baseline separation

- Current development baseline: P1-45 (`FilterKit-NEW`).
- Historical capability reference only: `FilterKit-Plugin-Operations-Optimized-Next9.6R16.1-ImportFix`.
- R16.1 files are not copied into the current target wholesale. The changes below port specific observed behavior into the current architecture.

## R16.1 source facts used

1. `Core/Plugins/ApplicationDiscovery/FKApplicationDiscoveryService.swift` enumerates `allInstalledApplications`, falling back to `allApplications`, reads each app's `Info.plist`, and collects version/executable/icon metadata.
2. `App/Features/Plugins/Applications/ApplicationDiscoveryView.swift` tries the literal icon path, `.png`, `@2x.png`, `@3x.png`, `.jpg`, and `@2x.jpg` off the main thread.
3. `Core/Diagnostics/ReadOnlyDiagnosticsEngine.swift` classifies system apps by bundle path (`/Applications/` or `/System/`), enumerates the supported DynamicLibraries layouts, reads dpkg `status` and `info/<package>.list`, and maps exact file paths to package owners.
4. `Core/Plugins/Repository/FastPluginInventoryEngine.swift` explicitly omits the full dpkg ownership/checksum diagnostic pipeline. That explains why R16's fast plugin surface and full diagnostics have different package metadata coverage.

## P1-46 changes

### App inventory parity

- Restore R16's path-first system-app classification rule: only `/Applications/` and `/System/` are system paths; apps in ordinary application containers (including TrollStore IPAs) are user apps even if LaunchServices reports `applicationType = System`.
- Relax bundle identifier filtering to the R16 contract (non-empty, bounded identifier) rather than requiring a strict dotted reverse-DNS syntax.
- Keep current LaunchServices multi-source enumeration and container-directory fallback; retain current model, cache, search, association, and settings behavior.
- Expand icon candidates to include the R16 literal-path and common PNG/JPEG scale variants, `Resources/` candidates, and nested `CFBundlePrimaryIcon.CFBundleIconName`. Candidate creation no longer depends on `fileExists` succeeding before UIKit gets a read attempt.

### Plugin inventory parity

- Read-only plugin inventory now aggregates all usable third-party plugin directories reported under the already-resolved jailbreak root. If the locator reports multiple populated directories, scanning those known directories is safe for inventory and avoids returning an empty list solely because one directory could not be selected as the sole source.
- Every item retains the original dylib/plist/manifest file paths for hashing, Mach-O inspection, plist parsing, and dpkg ownership lookup. The scan result also records all scanned directories. Backup export/import conflict checks use that full directory set, and backup export reads each item from its recorded source directory. Case-insensitive basename collisions remain invalid and are never resolved by arbitrary selection.
- Dpkg ownership lookup now builds a read-only in-memory index from the first readable dpkg `status` database and its installed package `.list` files. It supports logical rootless paths (for example `/usr/lib/TweakInject/X.dylib`) matching physical files below JBROOT, and returns package ID/version evidence.
- This restores package ownership attribution for files found in DynamicLibraries directories. It does not treat every package as a plugin: a package is represented in the plugin inventory only when its owned file is actually discovered as a `.dylib`/`.plist` in a supported plugin directory.

## Safety invariants

- No dpkg/APT process invocation.
- No writes, renames, chmod, deletes, or injection changes.
- No package ownership evidence is promoted to FilterKit ownership.
- Existing SHA-256, Mach-O, manifest verification, identity-conflict, and management-permission checks remain in place.
- Multiple real files with the same case-insensitive basename remain an explicit collision.

## Tests added/updated

- TrollStore / normal application container remains a user app despite LaunchServices `System` classification and hidden tags.
- R16-compatible nested/legacy icon metadata and file candidates.
- Aggregation of two populated plugin directories while preserving orphan states.
- Dpkg logical rootless `.list` path maps to a physical JBROOT file and retains package version.

## Validation status

- `swiftc -frontend -parse` over all `Sources` and `Tests/UnitTests` Swift files: passed.
- XCTest execution: not run in this environment (no Xcode/iOS SDK runtime available).
- Xcode iOS build: not run in this environment.
- Jailbroken-device acceptance: pending. App count, actual icon decode rate, selected jailbreak root, plugin file count, and dpkg ownership coverage must be checked on the target device.

### Executed local checks

- Swift syntax parse over all app source and unit-test files: passed.
- Targeted Swift type-check of the plugin scanner/model/backup-service dependency set: passed.
- Executable DPKG fixture (logical `/usr/lib/...` list entry to physical JBROOT file): passed.
- Executable multi-directory plugin inventory fixture: passed.
- Executable multi-directory backup read fixture (per-item absolute source paths): passed.
- Executable icon descriptor fixture (nested asset name and R16-compatible scale candidates): passed.
- Full XCTest suite and iOS/Xcode build remain unrun because this environment has no `xcodebuild` or Apple iOS SDK.
