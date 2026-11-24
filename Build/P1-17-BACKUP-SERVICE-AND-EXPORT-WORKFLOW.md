# P1-17 — Backup Service and Export Workflow

## Scope

P1-17 connects the P1-16 FilterKitBackup codec to the read-only plugin inventory and adds a user-facing batch export action. It does not deploy or restore plugin files.

## Implemented

- `FilterKitBackupService` builds Schema 2 archives from explicitly selected plugin UUIDs.
- Export requires a resolved, canonical plugin directory and a scanner record with `FilterKit` ownership, `canModify == true`, no ownership conflict, and an acceptable identity status.
- The service re-reads the dylib, plist, and `.fk.json` manifest from disk, rejects symlinks/non-regular files/path traversal/oversized files, and rechecks file hashes against the inventory and Manifest.
- Schema 3 Manifest content is included byte-for-byte with its SHA-256; hard binding and individual soft-association enabled states are preserved.
- The generated archive is passed through the existing P1-16 codec before it is returned.
- Import inspection and restore-preview entry points accept backup data or a selected backup file URL. They validate archive contents and report installed-App/file/plugin conflicts; they do not write to the plugin directory.
- Plugins page adds an export action for all currently manageable FilterKit-owned plugins and presents the resulting `.filterkitbackup` through the iOS share sheet.

## Safety boundaries

- Package-manager and unknown-source plugins are rejected.
- A plugin whose manifest, ownership, or file hashes changed after scanning is rejected.
- No dpkg command is invoked.
- No target App Bundle is modified or re-signed.
- No plugin is installed, overwritten, enabled, disabled, or deleted.
- Temporary archive output is created only when the user invokes export; it is not a deployment staging directory.

## Not implemented in this phase

- Actual restore/deployment execution.
- Helper integration or privileged writes.
- Automatic migration of hard-bound App identity.
- UI restore picker and conflict-resolution actions.

## Validation

See `TEST-REPORT-P1-17.md`. Xcode/iOS SDK build, XCTest execution, and RootHide/Rootless device validation require an Apple build/device environment and are not claimed here.
