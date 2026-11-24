# P1-15 — Manifest Schema 3 and Association-State Compatibility

## Goal

Give each soft App association a durable desired enabled state while retaining the immutable hard-bound source App. This phase defines and validates the data format, migration preview, and backup compatibility. It does not write manifests or deploy injection configuration.

## Manifest schema 3

Schema 3 retains the schema 1/2 identity and file-binding fields and adds:

```json
"softAssociatedBundleIdentifiers": ["com.example.secondary"],
"softAssociations": [
  { "bundleIdentifier": "com.example.secondary", "isEnabled": false }
]
```

- `softAssociations` is authoritative for each soft App's desired state.
- `softAssociatedBundleIdentifiers` remains as a compatibility index and must contain exactly the same Bundle ID set.
- Bundle IDs must be valid and unique; the hard-bound Bundle ID cannot also be a soft association.
- Schema 3 requires a valid hard-bound Bundle ID and a Mach-O identity digest.
- Dylib and plist filenames are leaf names only; both SHA-256 fields and the Mach-O identity digest must be valid.
- The scanner accepts schema 1, 2, and 3. Schema 1 remains file-hash-bound; schema 2/3 additionally require the binary identity digest to match the inspected Mach-O.

## Migration policy

- Schema 1/2 are decoded without changing their source bytes.
- Legacy soft associations have no per-App enabled bit. The compatibility rule is to interpret each recorded soft association as desired enabled.
- Migration preview creates an in-memory schema 3 value and emits a warning when legacy associations are interpreted as enabled.
- The caller must supply the actual dylib SHA-256, plist SHA-256, and current Mach-O identity digest. Schema 2/3 identity must match the current digest; changed files or binary identity are rejected.
- Schema 1 migration requires a currently computed binary identity digest; it does not claim the old manifest had one.
- Schema 3 creation and JSON encoding are provided as pure functions. No filesystem write is provided.

## Backup compatibility

- `FilterKitBackupDocument.currentSchemaVersion` is 2.
- Backup schema 1 entries contain only the soft Bundle ID list; restore compatibility interprets those associations as enabled.
- Backup schema 2 entries must contain explicit soft association states, and the explicit state Bundle ID set must match the legacy compatibility list.
- Duplicate, malformed, or hard-bound-as-soft associations are rejected.
- Backup payload hash verification and App-existence checks remain separate restore responsibilities; this phase does not perform restore or file writes.

## Safety boundary

1. No Helper write, manifest replacement, dylib/plist deployment, or target App modification.
2. No change to the unverified ElleKit Filter.plist matching/merge semantics.
3. No automatic hard-bound migration when the source App is missing.
4. No inference of runtime load success from manifest state.
5. Only already-authorized FilterKit-owned plugins may eventually use this schema; P1-12 ownership and identity-conflict gates remain in force.

## Files changed

- `Sources/Core/Models/PluginScanModels.swift`
- `Sources/Core/Models/PluginManifestSchemaMigration.swift`
- `Sources/Core/Models/BackupModels.swift`
- `Sources/Environment/ReadOnlyPluginScanner.swift`
- `Tests/UnitTests/PluginManifestSchemaMigrationTests.swift`
- `Tests/UnitTests/BackupAssociationCompatibilityTests.swift`
- `Build/TEST-REPORT-P1-15.md`
