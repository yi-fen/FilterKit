# P2-41 Changelog

- Added P2-41 plugin lifecycle, page responsibility, ownership, export/import and restore policy specification.
- Wired read-only dpkg package ownership evidence into the existing PluginScanRegistry inventory scan.
- Kept non-package/unverified files as unknown; package ownership evidence never grants FilterKit ownership.
- Added package-managed exact SHA-256 duplicate skip to restore preview.
- Defaulted restore preview to requiring at least one installed associated App.
- Allowed restore when Fixed Owner is absent but an Additional App Association is installed; original topology is preserved.
- Added restore preview counts for skipped entries.
- Added unit test coverage for the new restore policy.
- No production write/Helper/release gate was opened.
- Added Settings preference `Restore plugins for installed Apps only`, default on; it changes restore preview policy only and does not trigger inventory scanning.
- Restore preview UI now reports skipped count and explicit reasons for unassociated-App skips and external package-managed duplicates.

## P2-42 development increment

- Added a centralized, read-only plugin lifecycle policy with explicit APP/Plugin entry-point ownership.
- Encoded uninstall preconditions: FilterKit ownership, verified dylib/plist pair, verified manifest, and every per-App activation disabled.
- Encoded immutable Fixed Owner and the rule that an enabled Additional App Association must be disabled in APP before removal in Plugin.
- Modeled App availability as derived from installed Bundle IDs; uninstall/reinstall does not mutate Fixed Owner or Additional App Association topology.
- Hardened the Helper deployment execution boundary to preserve an explicit `packageOwned` denial on the final package-database recheck and recheck first-install destination absence immediately before transaction creation. The transaction itself continues to enforce absent targets under its process lock.
- No production mutation or release gate was opened. This increment does not claim that actual injection, activation, or uninstall execution is released.

- P2-42: Added Helper-side final SHA-256 duplicate detection for dpkg-managed dylibs listed in the configured plugin directory; exact external duplicates are rejected both during authorization and immediately before the atomic transaction.
