# P1-50 — Final App & Plugin Inventory Audit

## Baseline
- Mainline: P1-49 App Icon & Plugin Inventory Repair.
- Reference sources inspected: uploaded R16.1 source (`FKApplicationDiscoveryService.swift`, `FastPluginInventoryEngine.swift`) and TrollFools 4.4-257 (`AppListModel.swift`, `App.swift`, `EjectListModel.swift`).
- P1-50 is the final read-only inventory/UI refinement before plugin activation and injection work. It does not enable, disable, inject, install, or modify plugins.

## User-visible plugin row
Each plugin row now has three lines:
1. Plugin display name.
2. `filename.dylib  Paired` / `filename.dylib  Unpaired` (localized).
3. Associated App name(s), followed by source classification.

Association display rules:
- FilterKit manifest: show the declared hard-bound App name (and soft-associated App names when present). The manifest is parsed only for the bounded association projection; this does not verify its hashes or binary identity.
- Non-FilterKit plugin: resolve `Filter.Bundles` against installed bundle identifiers and `Filter.Executables` against installed executable names.
- Wildcard `*`: display a global association label.
- Unmatched targets: display a clear no-match / executable-target status rather than inventing an App name.
- Source is explicit: FilterKit, FilterKit manifest (unverified), package manager, or unknown/unverified. The fast inventory does not query DPKG just to decorate rows.

## Source audit findings and changes

### App discovery
- R16.1 and TrollFools both use LaunchServices (`allInstalledApplications` with `allApplications` fallback) as the primary inventory source.
- P1-49 already read each app's Info.plist once, kept the container walk as a fallback, and lazily resolved icons. User device testing confirmed Chrome, QQ Browser, and Dopamine-RootHide icons now display correctly; these icon paths were preserved.
- P1-49 had a short-lived cache per view model. Apps and Plugins screens could therefore enumerate LaunchServices separately after tab navigation. P1-50 introduces one shared 60-second cache registry for both screens, matching R16's shared-result design. Explicit App refresh still bypasses the cache.
- App discovery remains read-only. No bundle contents, LaunchServices database, or app metadata are modified.

### Plugin discovery
- R16.1 `FastPluginInventoryEngine` enumerates the supported ElleKit / MobileSubstrate / TweakInject locations, reads adjacent Filter plists, and computes static association matches against installed Apps. P1-49 already adopted the fast inventory principle and aggregate read-only directory enumeration.
- P1-49 decoded each valid plist once for a preliminary parse and again in `PluginFilterConfiguration.parse`. P1-50 removes the redundant first decode; the configuration parser is the single plist parse path.
- FilterKit manifest verification remains deferred, but P1-49 did not expose hard-bound metadata in the list because it skipped manifests entirely. P1-50 reads only a size-bounded manifest projection (maximum 64 KiB) to show hard-bound and soft-associated bundle IDs. It does not validate file hashes, Mach-O identity, ownership, or grant write permission.
- P1-49 constructed a DPKG ownership provider and retained package-evidence / full-manifest verification helpers inside the fast scanner, but the fast scan did not call those helpers. P1-50 removes this dead code and the unused DPKG dependency from the list scan. DPKG and full verification belong to the explicit detail/authorization phase, not inventory rendering.
- Unknown or unverified plugins remain visible and read-only. Pairing state is presentation-only and does not affect authorization.

## Remaining intentional costs / safety checks
- Directory existence, readability, canonical-path, symlink, and regular-file checks remain. These checks prevent the fast scan from following untrusted symlinks or treating directories as plugin files; they are not removed for a small speed gain.
- PluginDirectoryLocator inspects candidate directory contents to determine populated/ambiguous state, and the scanner later enumerates the selected/aggregated directories to build the inventory. This is a second directory listing. Removing it would require changing the assessment model to carry a stable inventory snapshot; that is deferred rather than weakening path validation in this final scan release.
- Each plugin plist is still read and parsed once because its Filter data is required for App association display.
- FilterKit manifests are size-bounded before decode. No dylib bytes, SHA-256, Mach-O slices, CDHash, or DPKG ownership are read in the fast path.
- App icon resolution remains lazy and cached. No broad synchronous icon decoding was added to LaunchServices enumeration.

## Reference boundaries
- TrollFools' bundle-ID icon lookup was already adopted in P1-49 and validated by the user's device report.
- TrollFools' App-scoped injected-asset operations are not a replacement for global ElleKit DynamicLibraries inventory. They are not copied into this phase.
- R16.1's static Filter plist matching is used only to present association labels. A plist match is not proof that a plugin is currently loaded or injected into a process.

## Files changed in P1-50
- `Sources/Environment/ReadOnlyPluginScanner.swift`
- `Sources/Environment/CachedAppDiscoveryProvider.swift`
- `Sources/Features/Apps/AppsView.swift`
- `Sources/Features/Plugins/PluginsView.swift`
- `Tests/UnitTests/ReadOnlyPluginScannerTests.swift`
- `Build/P1-50-FINAL-INVENTORY-AUDIT.md`
- `Build/P1-50-CHANGELOG.md`
- `Resources/en.lproj/Localizable.strings`
- `Resources/zh-Hans.lproj/Localizable.strings`

## Validation
- All Swift files in `Sources` and `Tests`: `swiftc -frontend -parse` passed.
- English and Simplified Chinese `.strings`: `plutil -lint` passed.
- XCTest / Xcode build: not run in this Linux environment; Xcode and iOS SDK are unavailable.
- RootHide device scan and performance timing: not re-run here. Existing user-confirmed P1-49 icon and plugin scan results remain the device baseline.
- No DEB was built and no package was installed.

## Next phase boundary
P1-50 closes inventory work. The next phase is plugin activation / injection, beginning with an explicit state model and read-only preflight, then a narrowly scoped Helper-mediated transaction with backup, atomic file updates, rollback, and post-operation verification. UI visibility, plist association, or a FilterKit manifest alone must never be treated as proof of safe activation or runtime injection.
