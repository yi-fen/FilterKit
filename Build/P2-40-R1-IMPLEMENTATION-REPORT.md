# P2-40-R1 — dylib inspection and automatic Filter.plist generation

## Scope implemented

- Added `PluginImportInspector` as a read-only import inspection component.
- Reads a selected `.dylib` and validates it through the existing bounds-checked `MachOMetadataReader`.
- Extracts architecture, install name, Mach-O current/compatibility versions, code-signature metadata state, and SHA-256.
- Accepts an optional original plist. It must be a property-list dictionary and is fingerprinted without rewriting its bytes.
- When no plist is supplied, generates an XML property list with only `Filter.Bundles = [targetBundleIdentifier]`.
- Does not guess `Classes`, `Executables`, `Mode`, or vendor-specific keys.
- Validates the target bundle identifier and enforces inspection size limits (256 MiB dylib, 4 MiB plist).
- APP detail importer now permits selecting one dylib and an optional plist together, obtains security-scoped access, and displays a read-only metadata/configuration preview.
- Added XCTest coverage for generated configuration and bundle identifier validation.
- Added a portable host smoke test covering dylib-only generation, architecture extraction, hash generation, and original-plist preservation.

## Explicitly not implemented in R1

- No installation, staging, deployment, or Helper IPC is performed.
- No production release gate was opened or changed.
- ZIP and DEB parsing are reserved for subsequent P2-40 phases.
- No claim is made that Mach-O code-signature metadata extraction constitutes trust verification.
- The generated plist is returned as `Data` and shown in the preview; the installation pipeline will persist it into the Helper-owned staging area in a later phase.

## Validation

- Swift parser validation: `PluginImportInspection.swift`, `AppsView.swift`, and the new XCTest source.
- Swift host type-check: SHA256, Mach-O metadata reader, filter parser, and import inspection model.
- Host smoke: PASS (10 assertions), using a synthetic arm64 Mach-O header and generated/original plist fixtures.
- Full Xcode/iOS build and XCTest execution were not available in this Linux environment; device acceptance remains pending.
