# Stage 2.4 — 0.1.18 Read-only diagnostics port record

## Scope and baseline

This change is an additive Swift port of the supplied `FilterKit-0.1.19-source.zip` diagnostic reference and its 18-item checklist. It is applied only under the R4-B2 `Source/FilterKit-DevDocs-0.1` tree. Existing package/build scripts and all `Artifacts` directories are left untouched.

The Objective-C reference is not copied into the Swift application target. The diagnostic logic is implemented in Swift and is compiled as part of the SwiftPM `Core` target.

## Added files

- `Core/Diagnostics/ReadOnlyDiagnosticsEngine.swift`
  - JBROOT candidate collection and structural checks; optional `jbroot()` / `jbrand()` runtime symbol lookup.
  - ElleKit / MobileSubstrate / TweakInject DynamicLibraries directory probing and dylib enumeration.
  - Filter plist reading and conservative Bundles / Executables / Classes parsing, including orphan plist records.
  - Injector evidence from dpkg package identifiers and current-process dyld images; compatibility profile fields remain profile data, not runtime proof.
  - dpkg status parsing, `.list` ownership, package metadata, file existence/readability, MD5 comparison, mismatch classification, source classification, ownership conflicts, and dual-channel Conffiles collection.
  - RootHelper candidate and LaunchDaemons reverse lookup without launching, signaling, communicating with, or installing a helper.
  - Installed App enumeration through guarded `LSApplicationWorkspace` selectors, bundle metadata/icon-file candidate inspection, and static plugin-to-App matching.
- `Core/Diagnostics/ReadOnlyFileHasher.swift`
  - Streaming MD5 + SHA-256 in one pass. SHA-256 is available for comparing an original file and a backup copy; this module does not create or restore backups.
- `Core/Diagnostics/AssociationSnapshotStore.swift`
  - Optional atomic JSON persistence restricted to a caller-supplied URL inside the FilterKit app sandbox. It is not called automatically by the scanner.

## UI integration

`DiagnosticsViewModel` now exposes an explicit `runReadOnlyDiagnostics()` action. `DiagnosticsView` adds a button; scanning is not automatically triggered at app launch. Results are appended as separate diagnostic sections, preserving the existing report/probe sections.

## 18-item coverage map

| # | Capability | Swift implementation |
|---|---|---|
| 1 | JBROOT location and validation | `discoverJBRoots`, `roothideJBRoot`, `roothideJBrand` |
| 2 | DynamicLibraries directory accessibility/enumeration | `discoverDynamicLibraryDirectories` |
| 3 | dylib enumeration | `scan()` directory inventory |
| 4 | Filter plist read | `scan()` plist inventory |
| 5 | Bundles / Executables / Classes parsing | `scan()` property-list parser |
| 6 | Injector recognition and compatibility profile | `identifyInjectors`, `runtimeInjectorImages`, `injectorProfile` |
| 7 | dpkg status parser | `parseDpkgStatus` |
| 8 | dpkg `.list` ownership | `analyzeDpkg` |
| 9 | Package metadata | `analyzeDpkg` package result fields |
| 10 | Installed-file existence/readability | `analyzeDpkg` file inventory counts |
| 11 | MD5 checks and SHA-256 backup comparison helper | `md5File`, `ReadOnlyFileHasher` |
| 12 | dpkg / manual-inferred / unknown source | plugin source classification after ownership analysis |
| 13 | Cross-package ownership conflicts | `fileOwnership[].conflict` |
| 14 | RootHelper preflight and LaunchDaemons reverse lookup | `inspectHelpers` |
| 15 | Installed App enumeration | `scanInstalledApplications` |
| 16 | App metadata and icon-file candidate | `scanInstalledApplications` |
| 17 | Static plugin↔App association and optional sandbox persistence | `buildAssociations`, `AssociationSnapshotStore` |
| 18 | status Conffiles + `.conffiles` merge | `conffilePaths` |

## Safety and interpretation rules

- All device inspection is read-only. No plugin enable/disable, plist/configuration edits, dylib moves/deletes, dpkg writes, symlink changes, process injection, Helper launch, Helper IPC, `launchctl`, or privileged daemon is implemented.
- `loaded` is always `unknown` in this diagnostic port unless an independent runtime signal is introduced later. A static Filter match is not injection success.
- Current-process dyld image evidence is explicitly scoped to the current process; it is not a global process inventory.
- MD5 is used only because dpkg `.md5sums` records use MD5. It is not a security signature.
- Mach-O checksum differences are classified as warnings because patching, signing, relocation, or other causes cannot be inferred from a digest mismatch alone.
- Private `LSApplicationWorkspace` calls are guarded and may return no app records on unsupported OS versions or sandbox contexts.
- The association persistence helper only accepts a path under `NSHomeDirectory()` and is not automatically invoked.

## Validation performed in this environment

- `swiftc -typecheck` passed for the three new diagnostic engine/helper files on the available Linux Swift toolchain. Darwin-only, CommonCrypto, UIKit, and Objective-C runtime branches are conditionally compiled and were not typechecked on an Apple toolchain.
- `swiftc -parse` passed for the modified diagnostics ViewModel and View.
- A Linux smoke run completed without mutation and produced a report (`findings=8`); the host dpkg database was visible in that environment, so the package count is not a RootHide-device result.
- No Xcode build, Theos build, DEB build, installation, or RootHide/Rootless device validation was performed here.

## Runner build feedback (run 44820826563, macOS SwiftPM non-UI build)

First Apple-toolchain compile of this port (Linux `swiftc -typecheck` had excluded Darwin / CommonCrypto / UIKit / Objective-C branches). Checkout `f13989a0846aa82c4dda6f813b16a9a08bdab93c`; Models / Adapters / AppPresentation emitted, Core emit-module failed with four diagnostics, all in `Core/Diagnostics/ReadOnlyDiagnosticsEngine.swift`:

- L275 / L288: `cannot find 'RTLD_DEFAULT' in scope` — `RTLD_DEFAULT` is the C macro `((void *) -2)` (dlfcn.h:97); pointer-cast macros are not imported into Swift. Fixed by a private static `rtldDefaultHandle: UnsafeMutableRawPointer? = UnsafeMutableRawPointer(bitPattern: -2)`; both `dlsym` calls pass that handle instead of the macro. Symbol names and `@convention(c)` aliases are unchanged; absent symbols still return `nil`.
- L554: `'close()' is only available in macOS 10.15 or newer`; L555: `'read(upToCount:)' is only available in macOS 10.15.4 or newer`. Fixed by switching `fileCategory(path:physicalPath:)` to the legacy `closeFile()` / `readData(ofLength:)` FileHandle APIs; `sample` is now non-optional `Data`. The package `platforms:` declaration and Deployment Target were left untouched (B1/B2/B5 still pending); no `@available` or `if #available` was added.

Diagnosis archive: `Tests/Stage2/evidence/run-44820826563-non-ui-build/run-44820826563-b2-non-ui-swift-build-compile-diagnosis.md`. Local static checks only (Linux host, no Swift/Xcode): brace/paren balance, residual modern-API scan, `dlsym`/`RTLD_` reference review. Core emit-module success and the downstream `swift test` suite remain pending Runner re-run.

## Remaining Apple/device validation

1. Build with the same Xcode/runner configuration as the successful R4-B2 baseline.
2. Validate `jbroot()` / `jbrand()` signatures and the private Workspace selector behavior on RootHide arm64e.
3. Validate Rootless path mapping, dpkg path mapping, and ElleKit directory reachability on a Rootless device.
4. Compare checksum mismatch buckets against real patched/resigned Mach-O and Conffiles fixtures.
5. Verify UI responsiveness and the complete diagnostics report on-device.
