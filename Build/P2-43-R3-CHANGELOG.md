# P2-43-R3 Changelog

## Scope

P2-43-R3 closes the first-injection binding gap between the deployed Filter.plist and the ownership Manifest. A successful first install now prepares Schema 4 binding topology, with the importing App as the immutable Fixed Owner and its activation bit enabled by default.

## Changes

### 1. Shared first-install binding policy

Added `PluginFirstInstallBindingPolicy`.

- Creates a Schema 4 Manifest with a Fixed Owner and explicit `fixedOwnerIsEnabled = true`.
- Preserves each supplied Additional Association's independent enabled bit.
- Rejects invalid Bundle IDs, case-insensitive duplicate associations, and an association that aliases the Fixed Owner.
- Requires Filter.plist Bundle targets to equal exactly the Fixed Owner plus enabled Additional Associations.
- Preserves original Bundle ID spelling in Manifest values; canonical keys are used only for identity comparison.

### 2. Production Helper first-install authorization

`HelperProductionDeploymentBackend.authorizeFirstInstall` now uses the shared policy and issues a Schema 4 ownership proof. The manifest is still deployed together with dylib and Filter.plist through the existing three-file transaction.

### 3. Root bootstrap parity

`HelperFirstInstallManifestBootstrap` uses the same binding policy and emits Schema 4 proof metadata. Case-variant duplicates and owner collisions are rejected consistently.

### 4. Update compatibility

- Existing Schema 3 plugins remain Schema 3 when updated; their legacy implicit-enabled Fixed Owner semantics are preserved.
- Schema 4 plugins remain Schema 4 across payload updates.
- Schema 4 update authorization verifies topology and soft-association mirrors before preserving Fixed Owner activation and each Additional Association state.
- No update path changes an App's activation bit as a side effect.

### 5. Regression tests

Added `PluginFirstInstallBindingPolicyTests` covering Schema 4 first-install topology, owner default-enabled behavior, independent association bits, Filter.plist target mismatch, canonical duplicate associations, and Fixed Owner collision.

## Product and security boundaries

- APP remains the only first-injection and per-App activation entry point.
- Plugin remains the association/export/restore/uninstall entry point.
- This change does not open production execution Gates.
- This change does not claim to bind a Bundle ID cryptographically to the authenticated IPC peer; peer-to-App identity attestation remains a separate device-acceptance requirement.
- Existing package-manager ownership, Root Helper authentication, transaction Journal/Ledger, and three-file atomic transaction checks remain in force.
