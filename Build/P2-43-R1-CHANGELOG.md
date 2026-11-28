# P2-43-R1 Changelog

## Scope

P2-43 begins product lifecycle integration with the backup/export/restore path. This increment fixes Bundle ID identity comparisons across backup validation, export consistency checks, and restore App-availability projection. It does not enable production restore writes.

## Changes

### 1. Shared backup Bundle ID identity comparison

- Added `BackupBundleIdentity` as a comparison-only adapter over `HelperBundleIdentifierKey`.
- Original Bundle ID spelling remains unchanged in backup payloads and UI-facing data.
- Optional Fixed Owner identity, association sets, and association enabled-state mirrors are compared using canonical Bundle ID keys.
- Case-variant duplicate associations are rejected rather than collapsed or silently accepted.

### 2. Backup codec validation

- Schema 2/3 association mirrors now compare Bundle IDs case-insensitively.
- Manifest Fixed Owner and Additional App Association identities compare canonically.
- Schema 4 binding topology and legacy mirror association states are compared by canonical Bundle ID plus the original per-App enabled bit.
- A casing difference alone no longer invalidates a logically identical backup; a different enabled bit or duplicate canonical identity still fails validation.

### 3. Backup export consistency

- Export compares scanned Plugin Inventory identities against Manifest identities canonically.
- Fixed Owner spelling differences do not cause false ownership/topology mismatch.
- Association state validation still requires exact per-App enabled-state agreement.
- File hashes, Plugin ID, Mach-O identity, ownership, path safety, and package-manager conflict checks remain unchanged.

### 4. Restore App availability projection

- Installed Bundle IDs are canonicalized for matching against Fixed Owner and Additional App Associations.
- A case-only difference no longer causes an installed App to be reported missing or cause a plugin to be skipped.
- Missing App identifiers retain their original backup spelling.
- Restore selection, file-conflict handling, identity-conflict handling, and package-manager duplicate policy are unchanged.

## Security and product boundaries

- APP remains the only first-time injection and per-App enable/disable entry point.
- Plugin remains the only plugin management, association, backup, restore, and uninstall entry point.
- Plugin-page association edits do not modify retained per-App enabled bits.
- Backup restore remains preview/selection only in this increment; no production file restore is enabled.
- Helper authorization, ownership proof, transaction Journal, and production write Gates are unchanged and remain closed.
