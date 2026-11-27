# P2-37-R1 — APP Detail State Refresh, Isolation & Identity Evidence Bridge

## Scope

R1 hardens the P2-37 APP-detail activation state model. It remains preview-only and does not submit Helper mutations or change Filter.plist / Manifest.

## Changes

- `PluginScanRegistry` now assigns a monotonically increasing scan generation. Results from superseded detached scans are ignored, so a slow old scan cannot overwrite a newer refresh.
- Every scan start publishes `snapshotRevision`. APP-detail preview overrides are invalidated as soon as a new scan begins, not only after a successful result arrives.
- `AppPluginActivationPreviewLedger` keys values by `(pluginID, targetBundleIdentifier)`. Two Apps associated with the same plugin cannot share preview state.
- Preview values are cleared when the scan snapshot changes. The configured Filter state remains separately displayed as the read-only observation.
- `PluginIdentityVerificationResolver` centralizes the fail-closed interpretation of ownership, pairing, Mach-O kind, unique identity, manifest binary binding, plugin UUID, payload hashes, and management permission.
- Identity conflicts are rejected; missing/unverified evidence remains unverified. The current read-only scanner still reports unknown ownership and unverified manifest binding, so its entries do not gain operable switches.
- APP detail shows an inline refresh indicator while retaining the last successful inventory.
- Added English and Simplified Chinese strings for refresh and identity-conflict states.

## Safety

- Preview toggle only updates in-memory UI state.
- No Helper mutation request is created by the APP detail toggle.
- No Filter.plist or manifest write is performed.
- Hard binding remains immutable; its activation preview remains a separate per-App state.
- Third-party, unknown, conflicted, or unverified plugins remain read-only.
- All production Release Gates remain closed.
