# P2-42-R16 — APP activation state authority and multi-App consistency

## Baseline

- Input: `FilterKit-P2-42-R15-Source.zip`
- Input SHA-256: `f30e5cc40062d007731afd390db9cab17f8523a89f6e5ac9a26d83c1c9022918`

## Important defect found and fixed

The Helper activation Prepare and Commit handlers previously derived `expectedEnabled` only from `manifest.softAssociations`. The Fixed Owner is deliberately not stored in that array, so a Fixed Owner target was incorrectly interpreted as disabled. This could reject a valid APP-page activation request for the first-injected App and could mis-handle Schema 4 owner state.

Added `HelperAppPluginActivationStateReader` as the single strict resolver used by both Prepare and Commit:

- Schema 3 Fixed Owner follows the legacy contract and is enabled.
- Schema 4 Fixed Owner reads `bindingTopology.fixedOwnerIsEnabled`.
- Additional App Associations read their own persisted `isEnabled` bit.
- Missing, duplicate, unknown, or inconsistent mirrored association metadata returns `nil` and fails closed; it is never silently converted to disabled.
- Prepare and Commit use the same resolver, preserving the revalidation boundary.

## Product behavior retained

- APP page remains the only place for first injection and per-App enable/disable.
- A successful first injection defaults enabled.
- A later first injection of the same plugin into another App defaults that App enabled independently.
- Plugin-page manual association addition remains disabled by default.
- Plugin page manages Additional App Association membership and uninstall only; it does not change activation bits.
- Removing an association still requires the Helper's atomic Filter.plist + Manifest plan.
- Uninstall still removes the dylib, Filter.plist, and Manifest set; already-running processes may retain a mapped image until restart.
- No production mutation gate was opened.

## Files changed

- Added `Sources/Core/Models/Helper/HelperAppPluginActivationStateReader.swift`.
- Updated `Sources/Environment/Helper/Runtime/HelperRequestDispatcher.swift` to use the shared reader for both activation Prepare and Commit.
- Added `Tests/UnitTests/HelperAppPluginActivationStateReaderTests.swift`.

## Validation

- All 233 Swift files under Sources and Tests passed `swiftc -frontend -parse`.
- The new production model and its XCTest source passed standalone Swift module/type-check validation.
- Standalone compiled Swift smoke test: 6/6 checks passed (Schema 3 owner, Schema 3 association, Schema 4 owner, independently enabled/disabled Apps, unknown target fail-closed).
- `Project.yml` parsed successfully as YAML.
- English and Simplified Chinese localization: 510 keys each, no duplicates, identical key sets.
- Source audit confirmed activation Prepare/Commit both call the same resolver and all production write gates remain closed.

## Not executed

- No full Xcode/iOS build or XCTest runner execution (Xcode is unavailable in this Linux environment).
- No signed Helper, live IPC, RootHide/ElleKit device test, or on-device filesystem transaction test.
