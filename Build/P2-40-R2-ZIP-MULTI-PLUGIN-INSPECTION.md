# P2-40-R2 — ZIP Multi-Plugin Inspection

## Scope

This stage adds ZIP package selection from an APP detail import entry and read-only discovery/inspection of multiple `.dylib` entries in one archive. It does not install files, create durable backups, commit binding metadata, or activate plugins.

## Implementation

- Added ZIPFoundation 0.9.19 as a Swift Package Manager dependency for the FilterKit app target only.
- Added `PluginZIPArchiveInspector` to enumerate archive entries and inspect each `.dylib` independently through the existing `PluginImportInspector`.
- Matches only sibling `<dylib-basename>.plist` or `Filter.plist`; ambiguous matches fail closed. Missing plist uses the existing conservative Bundles-only generator for the APP from which import was initiated.
- Supports multiple dylibs in one ZIP as one preview batch. Duplicate dylib basenames fail closed because the current staging/install identity is filename-based.
- Rejects absolute paths, traversal components, backslashes, duplicate file paths, symlinks and special entry types.
- Limits archives to 512 entries, each expanded file to 256 MiB, total expanded content to 512 MiB, and rejects suspicious compression ratios above 100:1 for entries larger than 10 MiB.
- Does not write archive paths to disk. Individual plugin bytes are streamed into bounded memory and briefly written to a unique temporary directory solely for reuse of the existing Mach-O/plist inspector; the directory is removed after each plugin inspection.
- APP detail file importer now accepts one ZIP at a time and displays per-plugin metadata, hashes, matched/generated plist status and warnings.

## Verification performed in this environment

- Swift parser: passed for changed Swift files (`swiftc -frontend -parse`).
- Project.yml YAML parsing: passed; ZIPFoundation dependency is attached to the FilterKit app target.
- Xcode/iOS build: not run; this environment has no `xcodebuild` or `xcodegen`.
- XCTest: not run; dependency resolution and iOS test runner are unavailable here.
- RootHide/ElleKit device test: not run.

## Explicitly not completed

- Durable first-successful-import batch policy and binding commit.
- ZIP extraction into Helper-owned staging, backup generation, atomic dylib+Filter.plist installation and activation.
- Production Gate changes. All production mutation gates remain as in the source package.

## Next

P2-40-R3 should add DEB archive parsing and control/data archive inspection, then the import coordinator should unify dylib/ZIP/DEB previews before any Helper staging or production mutation work.
