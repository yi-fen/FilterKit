# P1-09 — Plugin Inventory and Ownership

## Scope

P1-09 connects the read-only plugin inventory to the Plugins tab. It does not import, enable, disable, modify, or uninstall plugins.

## Inventory source

The scanner consumes only the unique directory selected by `PluginDirectoryLocator`. Candidate layouts now include:

- `Library/ElleKit/DynamicLibraries`
- `Library/MobileSubstrate/DynamicLibraries`
- `library/MobileSubstrate/DynamicLibraries`
- `usr/lib/TweakInject`

`Library/TweakInject` remains an ElleKit component location and is not independently selected as a third-party plugin directory. Multiple distinct usable plugin directories remain `ambiguous`; the scanner fails closed instead of merging unrelated directories. Canonical aliases are collapsed by the locator.

## File inventory

- Enumerates regular `.dylib`, `.plist`, and `.fk.json` files.
- Skips symbolic links.
- Pairs dylib/plist by case-insensitive basename, consistent with the R16 inventory behavior.
- Detects case-insensitive basename collisions and marks them invalid instead of silently overwriting one candidate.
- Keeps orphan dylibs, orphan plists, malformed plist files, unreadable files, and non-Mach-O dylibs visible as separate states.
- Does not infer loaded state from disk presence.

## Ownership classification

Ownership remains the product's three-state model:

- `filterKit`: valid schema-v1 `.fk.json` manifest, exact file names, and matching SHA-256 for both dylib and plist.
- `packageManager`: exact file ownership found in an installed package's dpkg `info/*.list` file.
- `unknown`: neither source is proven, or a FilterKit manifest conflicts with dpkg ownership evidence.

The dpkg provider reads `status` and `info/*.list` files only. It never invokes dpkg/APT and never changes package-manager state. A readable status database without an exact file owner is not sufficient to label a plugin as package-manager-owned. It remains `unknown`; no guessed `manual` label is emitted.

## UI

- `FilterKit-managed` scope shows only verified FilterKit-owned plugins.
- `All plugins` also shows package-manager and unknown-source plugins.
- Rows show ownership and dylib/plist pairing state.
- Details show package identifier, hashes, hard/soft App association metadata where verified, and warnings.
- All views remain read-only.

## Validation

- Swift source parse: passed.
- Foundation plugin subsystem typecheck on Linux Swift 6.2: passed using a minimal protocol/environment stub because the full app depends on iOS SwiftUI/UIKit and Xcode SDK.
- Smoke tests: exact dpkg file ownership, package-manager classification, dylib/plist pairing, duplicate basename detection, and ambiguous-directory fail-closed all passed.
- Localization parity: 139 keys in each language, matched.
- XCTest source added for dpkg ownership and directory variants; XCTest was not run because Xcode/iOS SDK is unavailable in this environment.
- Full Xcode/iOS build, jailbreak device validation, and runtime loaded-image inspection were not performed.
