# P0-06 — Project modules and architecture boundaries

## Scope

P0-06 establishes source-level module boundaries, shared domain models, and service contracts. It does **not** claim that jailbreak discovery, ElleKit parsing, privileged deployment, import/archive extraction, backup I/O, or cache deletion are implemented.

## Module map

- `Core/Models`: stable domain types shared by features and services.
- `Core/Protocols`: service boundaries; concrete implementations are added only after target-environment verification.
- `Core/AppDiscovery`: future installed-app discovery adapter.
- `Core/PluginDiscovery`: future plugin enumeration and ownership classification.
- `Core/PluginImport`: future dylib/ZIP/DEB inspection, safe extraction, staging, and validation.
- `Core/PluginConfiguration`: future original/managed/effective plist processing.
- `Core/PluginAssociation`: future hard-binding and soft-association persistence.
- `Core/PluginDeployment`: future constrained deployment client and verified helper integration.
- `Core/PluginBackup`: future FilterKitBackup serialization, integrity checks, and restore.
- `Core/StorageManagement`: storage accounting and cleanup contracts. Protected plugin files and user backups are not cleanup categories.
- `Environment`: jailbreak detection, path resolution, ElleKit installation facts, and profile contracts.
- `Persistence`: repository boundaries; no database engine is selected in this phase.
- `Localization`: stable internal message codes, separate from translated UI strings.
- `DesignSystem` / `Features`: existing UI layer remains separate from privileged operations.

## Domain invariants

1. A plugin has at most one immutable hard-bound source App identity.
2. Soft associations are separate and may be changed by the user; they cannot replace the hard binding.
3. Ownership is tri-state: `filterKit`, `packageManager`, `unknown`. Only FilterKit-owned plugins may be modified or uninstalled by FilterKit.
4. Original plist bytes are retained independently from the effective generated plist.
5. Storage cleanup categories contain only FilterKit-managed caches and temporary data. Installed dylib/plist files and user backup files are deliberately excluded.
6. The UI must not pass arbitrary privileged destination paths or shell commands to a helper.
7. File deployment success is not equivalent to proof that a plugin loaded in a target process.

## Implementation sequencing

The contracts are intentionally thin. Concrete implementations require verified RootHide/Rootless profile behavior and device testing. No speculative ElleKit plist format, filesystem path, launchd activation behavior, or privilege mechanism is embedded here.

## Validation

Run `Build/Scripts/verify-architecture.py` and the existing project/localization checks. Xcode project generation, compilation, and device behavior still require macOS with Xcode and a suitable test device.
