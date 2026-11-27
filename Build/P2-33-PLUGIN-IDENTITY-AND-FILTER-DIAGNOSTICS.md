# P2-33 — Plugin Identity & Filter Diagnostics

## Scope

P2-33 fixes the missing read-only identification path reported after P2-31/P2-32. The previous inventory intentionally left Mach-O fields empty and only parsed basic plist data; the detail screen therefore displayed blank architecture/CDHash/signature fields even when a readable dylib existed.

## Changes

- `ReadOnlyPluginScanner` now performs bounded, read-only inspection of each dylib (maximum 128 MiB) and plist (maximum 2 MiB).
- Thin/fat Mach-O slices expose architecture, UUID, install name/version, CDHash, and CodeDirectory metadata: identifier, Team Identifier, flags and platform.
- Dylib and plist SHA-256 values are calculated for inventory evidence.
- `Bundles`, `Executables`, `Classes` and `Mode` are parsed and shown in plugin details. Boolean Mode values are rendered as `true`/`false`; non-string array entries are retained as property-list representations and flagged as partial rather than silently discarded.
- Plugin details now show the per-slice CodeDirectory metadata.
- Settings now show plugin Filter inventory counts and the ElleKit compatibility-profile match state. This is a read-only diagnostic, not a claim that injection is enabled or that an app-specific filter is committed.
- Settings also inspect FilterKit's own main executable and show its architecture, CDHash, signature state, Team Identifier and SHA-256. This identifies the app binary; it does not prove that FilterKit itself has been injected into another process.

## Security boundary

All inspection is read-only. The scanner does not load, execute, copy, modify or inject a plugin. Mach-O identity and CodeDirectory metadata are evidence only; they do not prove signature validity on their own, establish package ownership, or grant management permission. Ownership/manifest verification remains separate. All production mutation switches remain `false`.

## Validation

Run:

```sh
Build/Host/run-p233-plugin-identity-smoke.sh
python3 Build/scripts/p233_plugin_identity_audit.py
```

The host smoke builds a synthetic signed arm64 Mach-O with a CodeDirectory and a plist containing all four Filter fields, then validates the parser and read-only scanner projection.

A synthetic CodeDirectory test is not an Apple `codesign` validation and does not substitute for an iOS/RootHide device test. Xcode/iOS SDK build, XCTest on Apple platforms, signature verification against real binaries, and runtime injection remain unverified here.
