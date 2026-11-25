# P1-48 — Fast App and Plugin Inventory

## Scope
P1-48 optimizes the read-only inventory path using the uploaded R16.1 and TrollFools 4.4-257 source as references. It does not replace P1-47.3 packaging/signing work and does not broaden plugin mutation permissions.

## App discovery
- LaunchServices `allInstalledApplications` is the primary inventory.
- `allApplications` is queried only when the primary result is empty.
- A successful LaunchServices inventory no longer triggers a second full container-directory walk.
- Container scanning remains the fallback when LaunchServices is unavailable or empty.
- Existing metadata/icon extraction and cached discovery layers remain in place.

This follows R16.1's preferred/fallback LaunchServices strategy and TrollFools' use of `allApplications`; it intentionally does not import TrollFools-specific eligibility filtering.

## Plugin discovery
- All readable supported third-party DynamicLibraries directories are still aggregated.
- Dylib-only and plist-only entries remain visible.
- The fast inventory no longer reads/hashes dylib binaries, parses Mach-O slices, queries package ownership, or verifies FilterKit manifests.
- Adjacent plist data is still read to expose Filter configuration and App associations.
- Ownership remains unknown and management permission remains conservative until a separate detail-verification path is implemented. This avoids treating inventory visibility as authorization to modify files.

This adopts R16.1's separation of fast inventory from diagnostics. TrollFools' per-App injected/persisted asset enumeration is not substituted for global ElleKit directory discovery because the two inventories represent different scopes.

## Validation
- Source-level changes and unit-test expectations updated.
- Build/test execution status must be recorded separately; this package was prepared in a Linux environment without Xcode/iOS SDK.
- Device validation remains required for private LaunchServices behavior, RootHide paths/permissions, icon rendering and actual plugin visibility.
