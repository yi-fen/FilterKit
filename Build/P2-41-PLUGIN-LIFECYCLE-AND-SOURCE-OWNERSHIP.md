# P2-41 — Plugin Lifecycle, Source Ownership & Operation Boundaries

## Scope delivered

P2-41 establishes the shared product/domain rules for plugin lifecycle and source ownership. It adds read-only package ownership evidence to the single Plugin Inventory path and applies default restore filtering plus exact package-managed SHA-256 duplicate skipping to the restore preview.

This phase does **not** implement production injection, uninstall, restore writes, package-manager mutation, or UI navigation redesign. Existing production mutation gates remain closed.

## Frozen page responsibility

- **Home**: aggregate status and counts only.
- **APP**: the only first-time plugin injection entry point; per-App enable/disable only.
- **Plugin**: plugin metadata, extension-association management, backup restore entry, export, and uninstall. Uninstall is only available here.
- **Settings**: environment and global policies, including the restore filter preference.
- No first-time arbitrary dylib import from Plugin.
- The APP action label is **Inject Plugin**, replacing **Import Plugin**.

A backup restore is a controlled restoration of a FilterKit-owned record; it is not a new first-time injection and must preserve the original ownership and binding topology.

## Ownership and provenance

A plugin is manageable only when FilterKit ownership is positively established by the existing trusted manifest/Helper attestation chain. A filename, directory location, embedded manifest UUID, or SHA-256 alone is not ownership proof.

Read-only package-manager evidence is gathered from dpkg status and package `.list` files:

- A dylib or paired plist recorded as package-owned is classified `packageManager`.
- Conflicting package owners across the pair produce `multiplePackageOwners`.
- No package-owner evidence does **not** promote a file to FilterKit ownership; it remains `unknown` until the trusted FilterKit verification path proves otherwise.
- Unknown-source and package-manager files remain read-only.
- Other package managers or external tools not represented in the dpkg database remain `unknown` and therefore read-only.

The scanner receives this provider only through `PluginScanRegistry`; no second inventory scan/cache is introduced. The scanner remains read-only and does not invoke dpkg.

## Operation matrix

| Source | APP inject/enable | Plugin export | Plugin uninstall | Restore overwrite/adoption |
|---|---|---|---|---|
| Verified FilterKit-owned | Subject to Helper authorization and closed production gate | Yes, after full validation | Yes, after all App activations are off and Helper transaction is authorized | Never overwrite an existing file; exact existing identity is a duplicate/skip |
| Package-manager-owned (e.g. Sileo/dpkg) | Skip; do not add duplicate FilterKit injection rules | No | No | Exact dylib SHA-256 match: skip; different content at a conflicting path/identity: block |
| Other external tool | Skip/read-only unless trusted ownership is established | No | No | No automatic adoption; conflicts block |
| Unknown origin | Skip/read-only | No | No | No automatic adoption; conflicts block |

SHA-256 proves byte equality only. It does not prove provenance or ownership. Exact external duplicate handling must therefore report `externalDuplicate` and must not copy, overwrite, adopt, export, uninstall, or add a second injection rule.

A same filename with a different hash is a conflict, not a duplicate. A same Bundle ID/install identity with different bytes is an identity conflict and must block mutation. If source cannot be established, default to read-only.

## Fixed Owner and Additional App Association

- First successful FilterKit injection establishes immutable `Fixed Owner`.
- Fixed Owner is never removed, transferred, or replaced by an Additional App Association.
- `Additional App Association` can be added/removed only from Plugin.
- A newly added additional association defaults disabled.
- APP is the only place to enable/disable a plugin for an App.
- Each App has an independent activation state.
- App uninstall changes availability only; it does not delete plugin files or association Bundle IDs.
- Reinstalling the same Bundle ID reactivates the existing association; it does not create a new plugin or re-inject files.
- A missing Fixed Owner does not prevent restoring a plugin when at least one Additional App Association is installed.
- Fixed Owner and association topology are preserved exactly during backup/restore.

## Uninstall lifecycle

- Plugin uninstall is initiated only from Plugin.
- Before uninstall, every App activation for that plugin must be disabled in APP.
- Helper must verify ownership, identity, file observations, authorization, and the existing atomic dylib/plist transaction contract.
- Uninstall removes the plugin's managed payload and active association state. The implementation must not delete external package-manager files.
- Historical audit records may retain the original Fixed Owner identifier; an uninstalled plugin must no longer appear as an active managed inventory item.

## Backup/export

- Export only positively verified FilterKit-owned plugins.
- Include dylib, Filter.plist, manifest, SHA-256 values, plugin identity, Fixed Owner, all Additional App Associations, and independent per-App enabled states.
- App installation state does not filter export.
- Package-manager, external-tool, and unknown-origin plugins are never exported by FilterKit.
- Missing or mismatched payload/manifest/hash/identity blocks a successful export.

## Backup/restore

Default restore filtering is enabled:

- Import only if at least one Bundle ID in the plugin's complete binding topology (Fixed Owner plus all Additional App Associations) is currently installed.
- If Fixed Owner is absent but an Additional App Association is installed, restore is allowed and the original Fixed Owner remains unchanged.
- If no associated App is installed, preview reports `skippedNoInstalledAssociation`; the backup bytes and topology remain untouched.
- If the user disables the preference, restore preview includes plugins with no currently installed associated App, but reports missing Bundle IDs.
- Exact dylib SHA-256 already owned by a package manager reports `externalDuplicate` and is skipped before file-conflict handling.
- Same filename with different bytes, conflicting plugin identity, or conflicting path blocks restore.
- Skipped entries are not written to the local inventory and must not leave partial files.
- All archive, manifest, hash, identity, Helper authorization, and transaction checks remain mandatory for selected entries.

## Restore preview disposition semantics

- `ready`: no missing App association and no conflict.
- `softAppsMissing`: at least one association is installed, but one or more other associated Apps are absent; restore may proceed while preserving all Bundle IDs.
- `skippedNoInstalledAssociation`: default installed-App filter found no installed associated App.
- `externalDuplicate`: exact dylib hash is already package-manager-owned; skip without adoption.
- `fileConflict`: destination filename/path collision; block.
- `identityConflict`: existing plugin identity collision; block.
- Legacy `hardBoundAppMissing` remains decodable for compatibility but is no longer produced by the current policy.

## Implementation notes and remaining work

Implemented in this phase:
- Package ownership provider is wired into the existing `PluginScanRegistry` scan path.
- Scanner marks dpkg-owned files read-only and records package identifiers; multiple package owners are a conflict.
- Helper identity attestation promotes a candidate to FilterKit ownership only after root-side package ownership and root-owned manifest/payload verification; a Helper `package_manager_owned` rejection classifies it as external package-managed.
- APP injection inspection compares the candidate dylib SHA-256 against the shared package-managed inventory snapshot and explicitly marks exact matches `SKIP`; unavailable inventory fails closed pending a scan. Helper must still revalidate ownership immediately before any future mutation.
- Restore preview defaults to installed-associated-App filtering.
- Restore preview accepts package-managed dylib hashes and skips exact SHA-256 duplicates.
- Restore preview no longer treats a missing Fixed Owner as a hard block if another associated App is installed.
- Unit tests added for default filtering, extension-only availability, exact external duplicate skip, and filter override.

Not implemented yet:
- Settings now persists `filterkit.restore.onlyInstalledAssociatedApps`, defaults to `true`, and the restore preview consumes it without triggering a scan.
- Package ownership discovery for package managers that do not use the dpkg database.
- Full Helper-side duplicate-SHA revalidation immediately before any future write (required to close TOCTOU); current APP check is a preview guard only.
- Actual injection/uninstall/restore execution and signed-device acceptance.
- APP/Plugin UI responsibility refactor and all localized copy changes.

Production mutation and release gates must remain closed.
