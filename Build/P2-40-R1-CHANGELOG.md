# P2-40-R1 — Dylib Inspection and Filter.plist Pairing

## Product terminology

The user-facing terms are standardized as:

- **Fixed Owner App** (Chinese: **固定归属 App**): the immutable source/owner App recorded by the existing `hardBoundBundleIdentifier` manifest field.
- **Additional App Association** (Chinese: **扩展关联 App**): an independently removable association recorded by the existing soft-association records.

The on-disk schema and Helper protocol retain their existing `hardBound` / `softAssociation` field names. This is a UI terminology change, not a manifest migration. The fixed owner remains present and cannot be removed; additional associations do not replace it. Activation remains a separate per-App operation.

## Implemented in this revision

- Added `PluginImportFilePairResolver` for a selected `.dylib`.
- If the user did not explicitly select a plist, the resolver checks only conventional sibling names: `<DylibBaseName>.plist` and `Filter.plist`.
- If no sibling plist exists, the existing inspector generates a minimal Bundles-only Filter.plist for the App whose detail page initiated import.
- If both conventional plist candidates exist, the import is rejected as ambiguous rather than silently choosing a possibly unrelated configuration.
- Explicitly selected plist files take precedence.
- Symlinks and non-regular files are rejected by the pairing resolver.
- The App import review now displays the fixed-owner App and the post-install default activation intent, while clearly stating that this stage is read-only and performs no installation or activation.
- Added unit tests for conventional matching, no-plist generation path, and ambiguous candidates.
- Updated Chinese and English UI labels to “固定归属 / 扩展关联” and “Fixed Owner / Additional App Association”.

## Not implemented / release boundary

This R1 change does not implement ZIP/DEB extraction, persistent first-successful-batch tracking, backup creation, Helper staging, installation, or activation. Those require the subsequent package parser and verified Helper deployment stages. Production mutation gates remain closed. No claim of device acceptance is made.
