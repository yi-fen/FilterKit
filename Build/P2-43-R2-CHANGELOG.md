# P2-43-R2 Changelog

## Scope

P2-43-R2 continues lifecycle integration across APP activation state and Plugin association management. This increment closes case-sensitive Bundle ID identity gaps in lifecycle policy/projection and APP pending-operation row matching. It preserves the existing page ownership and Helper authorization boundaries.

## Changes

### 1. Lifecycle evidence projection uses canonical Bundle ID identity

- `PluginLifecycleEvidence.installedAssociatedBundleIdentifiers` now matches installed Apps through `HelperBundleIdentifierKey` while returning the original Manifest association spelling.
- `unavailableAssociatedBundleIdentifiers` uses the same canonical identity rule, so App uninstall/reinstall changes only the derived availability projection.
- Added a canonical per-App `isEnabled(bundleIdentifier:)` lookup. Activation bits remain independent and are not rewritten by availability changes.

### 2. Lifecycle association policy uses canonical identity

- Adding an association rejects a case-variant of the Fixed Owner.
- Adding an association rejects a case-variant of an existing Additional App Association.
- Removing the Fixed Owner remains forbidden even when the requested Bundle ID differs only by case.
- Removing an existing Additional App Association resolves by canonical Bundle ID identity.
- Original Bundle ID strings are not rewritten.

### 3. APP pending operation row matching

- The APP detail row now matches an in-flight activation command to the displayed App using canonical Bundle ID identity.
- A case-only spelling difference no longer hides the pending operation status or reconciliation affordance.
- Existing Helper transaction proof and command identity checks remain unchanged.

### 4. Lifecycle regression coverage

- Added tests for case-insensitive installed/missing App projection while preserving Manifest spelling.
- Added tests for independent enabled-state lookup.
- Added tests for Fixed Owner and existing association collision/removal behavior under case variants.
- Added a three-App topology test: removing one enabled association preserves the Fixed Owner state, another enabled App, and a disabled App.
- Existing import-batch tests continue to specify first successful injection establishes Fixed Owner and defaults enabled; later importing Apps receive an enabled Additional Association for that plugin.
- Existing Helper planner tests continue to require atomic removal of a removed active Bundle filter and prohibit Plugin-page changes to retained activation bits.

## Security and product boundaries

- APP remains the only first-time injection and per-App enable/disable entry point.
- Plugin remains the only association management, export, restore, and uninstall entry point.
- Plugin-page association creation defaults disabled; import-time first injection semantics remain separately governed by the import batch policy.
- Plugin-page association removal does not change retained Apps' enabled bits.
- Helper ownership proof, identity attestation, IPC authorization, Journal/Ledger transaction logic, and all production write Gates are unchanged and remain closed.
