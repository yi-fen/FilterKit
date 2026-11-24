# P1-06 — Read-only Plugin/App Association Projection

## Scope delivered

- Added a dedicated association read model separate from the filesystem scan model.
- Added `filterKitPluginID` to verified scan items. This value comes from the successfully verified `.fk.json` manifest, not from the dylib filename.
- Added `ReadOnlyPluginAssociationReader`, which combines verified FilterKit manifest association metadata with the installed-app inventory supplied by `AppDiscoveryProvider`.
- Preserves the hard-bound source Bundle ID independently from whether that app is currently installed.
- Resolves installed soft-associated apps and separately reports missing soft-associated Bundle IDs.
- Builds the effective Bundle ID list from currently installed associations only. If the hard-bound app is missing, its identity remains recorded but is not included in the effective list.
- Does not migrate a hard binding, rewrite a manifest, alter a plist, or write to the jailbreak filesystem.
- Skips association records without a valid manifest UUID or valid hard-bound Bundle ID. Non-FilterKit ownership records are not treated as FilterKit-managed associations.
- Added Chinese and English localized status keys.

## Data flow

`PluginDirectoryLocator` → `ReadOnlyPluginScanner` → verified `PluginScanResult` → `ReadOnlyPluginAssociationReader` + installed app inventory → `PluginAssociationReadResult`.

The association reader does not independently scan arbitrary paths. It consumes the verified scan result and the app inventory abstraction.

## Safety and invariants

- Exactly one hard-bound source identity is retained per plugin record.
- Soft associations never replace or mutate the hard-bound source identity.
- Missing apps are reported, not silently removed from persisted metadata.
- Effective associations contain only apps currently present in the installed-app inventory.
- No import, enable/disable, deploy, uninstall, plist generation, manifest update, or target-App modification is performed.
- The result is explicitly marked read-only.

## Validation performed

- Added XCTest coverage for installed hard-bound + installed/missing soft associations.
- Added XCTest coverage proving a missing hard-bound app does not migrate to an available soft-associated app.
- Localization key parity checked during packaging.
- Source-level typecheck and smoke validation are reported in `TEST-REPORT-P1-06.md`.

## Not validated

- Xcode/iOS SDK build and XCTest execution (Xcode is unavailable in this environment).
- Live installed-app discovery on Dopamine RootHide / Rootless devices.
- Actual FilterKit manifest files emitted by a deployed importer; importer/manifest writer is not implemented yet.
- UI rendering of association state; Plugins and Apps screens remain in their planned implementation phases.
