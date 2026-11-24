# P1-05 — Read-only Plugin Scanning & Ownership Classification

## Scope delivered

- Scans only the single canonical directory selected by `PluginDirectoryLocator`.
- Refuses to scan when the directory state is ambiguous, unavailable, or inaccessible.
- Enumerates regular files only; symbolic links are skipped and reported.
- Pairs `.dylib` and `.plist` by exact, case-sensitive filename stem.
- Reports paired files, orphan dylibs, orphan plists, unreadable files, invalid Mach-O headers, and invalid property lists.
- Missing plist is reported as `orphanDylib` with `plugin_scan.plist_generation_required`; P1-05 does not generate or write a plist.
- Reads only same-stem `<name>.fk.json` manifests, with a 64 KiB size limit and schema version 1.
- FilterKit ownership requires exact filenames plus matching SHA-256 hashes for both dylib and plist.
- Package-manager ownership is an injected read-only evidence provider. No `dpkg` command is invoked and no package database is modified.
- Conflicting verified FilterKit manifest and package-manager evidence results in `unknown` ownership plus a warning.
- Scan results include timestamp, canonical scan directory, directory state, plugin records, issues, hashes, and a read-only flag.
- Added Simplified Chinese and English localization keys and four XCTest cases.

## Safety boundaries

This phase does not import, deploy, enable, disable, uninstall, rename, chmod, or delete anything. It does not generate missing plist files. It does not infer ownership from directory paths or filenames. A manifest file by itself is not sufficient evidence. Package ownership integration remains an injected provider; until a verified read-only dpkg file-ownership source is connected, such plugins remain `unknown`.

## Validation performed in this environment

- Swift 6.2.1 Linux typecheck of scanner/model/SHA-256 code with minimal environment protocol stubs: passed.
- Executable smoke checks: SHA-256 known vector, exact-stem pairing, orphan dylib classification, invalid plist classification, and ambiguous-directory fail-closed behavior: passed.
- Localization key parity: checked separately in packaging validation.
- ZIP integrity: checked after archive creation.

## Not validated

- Xcode/iOS SDK build and XCTest execution (no Xcode toolchain available in this environment).
- Real Dopamine RootHide / Rootless device directory contents and permissions.
- Actual dpkg file-ownership provider integration.
- Real-world plugin `.fk.json` manifests from a deployed FilterKit build; schema v1 is the scanner contract introduced in this phase.
