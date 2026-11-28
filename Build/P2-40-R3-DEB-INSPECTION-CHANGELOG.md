# P2-40-R3 — Debian package inspection

## Implemented

- Added `PluginDEBArchiveInspector` for read-only Debian `.deb` inspection.
- Parses the Debian `ar` container, validates the `debian-binary` version marker (`2.0`), and locates `control.tar*` / `data.tar*` members.
- Parses uncompressed `control.tar` and `data.tar` members; extracts Package, Version, Architecture, and Maintainer metadata from the Debian control file.
- Finds multiple `.dylib` files in the data archive and matches sibling `Filter.plist` / `<dylib-name>.plist` files.
- Reuses the R1 `PluginImportInspector` for Mach-O metadata, SHA-256, original plist validation, and conservative Bundles-only plist generation.
- Adds entry-count, per-entry-size, total-expanded-size, path traversal, duplicate-path, and special-file checks.
- Does not execute Debian maintainer scripts or write package contents to jailbreak paths.
- Adds `.deb` to the APP-detail file importer and displays package/plugin inspection results.

## Explicit limitations

- This iteration accepts **uncompressed `.tar` members only**. Common compressed Debian members such as `.tar.gz`, `.tar.xz`, `.tar.zst`, and `.tar.bz2` are rejected with an explicit unsupported-compression error. No claim of general DEB compatibility is made yet.
- This remains a read-only inspection stage. It does not install, back up, activate, or commit bindings.
- Package scripts are never run.

## Validation performed in this environment

- Swift parser check for changed Swift files: passed.
- Standalone Swift typecheck of `PluginDEBArchiveInspector` against minimal import-model stubs: passed.
- Executed smoke test for Debian ar member parsing, control metadata parsing, and path safety: passed.
- Xcode/iOS build and XCTest execution: not run in this Linux environment.
- RootHide/ElleKit device acceptance: not run.
