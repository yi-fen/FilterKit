# P1-18 — FilterKitBackup Import UI and Restore Conflict Review

## Scope

P1-18 connects the existing P1-16 codec and P1-17 read-only backup service to the Plugins page. It intentionally stops before deployment. No plugin directory, manifest, plist, dylib, or injection rule is written.

## Implemented

- Added a Plugins-page backup actions menu with export and import entries.
- Added a document picker filtered to `.filterkitbackup` (codec validation remains authoritative).
- Opens security-scoped file access for the selected document and releases it after inspection.
- Validates the complete backup through `FilterKitBackupService.inspectBackup(at:)` before presenting any contents.
- Reads the installed App inventory and compares hard-bound and soft-associated Bundle IDs.
- Compares destination filenames and existing FilterKit plugin UUIDs when a uniquely resolved plugin directory is available.
- Displays plugin filename, restore disposition, hard-bound source App, missing App identifiers, and conflicting filenames.
- Supports per-plugin selection. `ready` and `softAppsMissing` entries may be selected; missing hard-bound App, file conflict, and identity conflict entries are blocked.
- Requires a final confirmation dialog. The confirmation explicitly states that it only records the user's review selection and does not restore files.
- If the destination plugin directory could not be scanned, the review shows that filename-conflict inspection may be incomplete.

## Safety boundaries

- No archive extraction is performed.
- No target App Bundle is modified or re-signed.
- No dpkg command/database mutation occurs.
- No plugin file, Manifest, plist, or injection rule is written, renamed, deleted, or chmod'ed.
- No injection success is inferred from backup validation.
- Soft-associated Apps missing from the device remain represented in the backup plan; they do not block selection by themselves.
- A missing hard-bound source App blocks selection; hard binding is never migrated automatically.
- Existing file or plugin-identity conflicts block selection; no overwrite path exists.

## Files changed

- `Sources/Features/Plugins/PluginsView.swift`
- `Sources/Core/Models/BackupModels.swift`
- `Resources/en.lproj/Localizable.strings`
- `Resources/zh-Hans.lproj/Localizable.strings`
- `Tests/UnitTests/BackupRestoreSelectionPolicyTests.swift`

## Validation

- Full Swift source/test syntax parse: PASS.
- Backup model and restore selection policy Foundation type-check with narrow supporting stubs: PASS.
- Standalone restore-selection smoke test: PASS.
- Localization parity: 225 keys in each language, no duplicates.
- Xcode/iOS SDK build: not available in this Linux environment.
- XCTest execution: not performed; test source is included.
- iOS document picker/security-scoped URL behavior: requires device/Xcode validation.
- RootHide/Rootless device validation: not performed.
