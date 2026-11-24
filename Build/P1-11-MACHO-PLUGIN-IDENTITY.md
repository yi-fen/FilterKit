# P1-11 — Mach-O Plugin Identity and Version Metadata

## Scope

P1-11 extends the P1-09 read-only plugin inventory with binary identity metadata. It does not change plugin ownership, management permissions, deployment, enable/disable behavior, or injection state.

## Mach-O parsing

`MachOMetadataReader` is a bounds-checked parser for thin and fat/universal Mach-O files. It reads load commands without loading or executing the inspected binary.

Per architecture slice it extracts:

- CPU type/subtype and normalized architecture label (including arm64 and arm64e)
- `LC_ID_DYLIB` install name
- `current_version`
- `compatibility_version`
- `LC_UUID`
- CodeDirectory-derived CDHash when the embedded code-signature blob is structurally readable and its hash type is supported

Fat32 and Fat64 containers are enumerated slice-by-slice. Malformed or unsupported slices are not silently interpreted as a valid identity. `read(data:architecture:)` requires the requested architecture to exist when one is specified.

## CDHash semantics and limits

The reader locates `LC_CODE_SIGNATURE`, parses either a direct CodeDirectory blob or an embedded-signature SuperBlob, and hashes the CodeDirectory bytes. SHA-1 and SHA-256 CodeDirectory hash types are supported, including the truncated SHA-256 variant. The displayed CDHash is the first 20 bytes of the CodeDirectory digest, in hexadecimal.

This is metadata extraction, **not** code-signature trust validation. It does not establish that a signature chains to Apple, is accepted by the device, or that the binary is currently loaded. Missing, malformed, or unsupported signatures produce an explicit state and no invented CDHash.

## Package version separation

`DpkgFileOwnershipProvider` now returns the `Version` field from the exact installed package stanza that owns the file through its `.list` entry. The Plugins detail view displays this as Package version.

The values remain separate:

- Package version: Debian/dpkg `Version`
- Mach-O current version: `LC_ID_DYLIB.current_version`
- Mach-O compatibility version: `LC_ID_DYLIB.compatibility_version`

No version is inferred from a filename or substituted across these sources.

## Inventory integration

The read-only scanner attaches per-slice metadata to `PluginScanItem`. The Plugins detail view displays install name, Mach-O versions, UUID, architecture list, CDHash, signature metadata state, and per-slice summaries. Existing SHA-256 file hashes, FilterKit manifest verification, and ownership classification remain independent.

Same basename is still only a pairing hint. P1-11 exposes stronger binary identity but does not yet merge or deduplicate plugins by UUID/CDHash, nor does it grant management rights based on a fingerprint.

## Safety

- Read-only file access only.
- No `dlopen`, code execution, file writes, chmod, rename, or deletion.
- No dpkg command invocation or database modification.
- No target App Bundle modification or re-signing.
- No claim that a disk-resident plugin is loaded in a target process.

## Remaining device validation

Real RootHide/Rootless dylibs are still required to validate fat-slice layouts, CodeDirectory variants, and CDHash agreement against platform tooling on the target iOS versions. iOS/Xcode compilation and XCTest execution are not performed in the Linux build environment.
