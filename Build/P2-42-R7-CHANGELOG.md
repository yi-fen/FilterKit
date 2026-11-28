# P2-42-R7 Change Log

## Plugin App-load scope classification

- Replaced the process-running indicator with a configuration-derived App-load scope.
- The Plugin row now distinguishes App Bundle ID targets, executable targets, global (`*`) targets, standalone plugins with a valid empty target configuration, and unknown/unverifiable configurations.
- Only the observed ElleKit filter's `Bundles` and `Executables` are treated as load-target evidence. Unverified Manifest Fixed Owner/Additional Association hints are not promoted into a load claim.
- App display names are resolved through the existing `PluginAppDisplayIndex`.
- A partially parsed filter with no positively identified target is not mislabeled as standalone.
- This is a read-only interpretation of the existing ElleKit filter and association snapshot. It does not write or rewrite any filter, Manifest, binding topology, or enable state.

## Removed process polling

- Removed `PluginHostProcessProbe` and its process enumeration from the Plugin screen.
- Removed the Plugin screen's five-second polling loop. App-load scope is derived synchronously from the current plugin snapshot and existing App-name index; it does not depend on whether the host App is currently running.
- The Plugin screen still uses the shared `PluginScanRegistry`; no second scanner or independent plugin inventory was added.
- The registry's pre-existing Helper-attestation freshness monitor is separate security maintenance, not Plugin runtime/status polling, and remains unchanged.

## Source wording

- Unknown plugin source is displayed as `来源：未知` / `Source: unknown`.
- No Manifest hint or unverified source metadata is promoted to FilterKit ownership.

## Safety

- No production injection, toggle, uninstall, association-write, or restore gate was opened.
- No jailbreak files or injection rules were modified.
