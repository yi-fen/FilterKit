# P2-41 Validation Report

Date: 2026-11-27

## Passed

- `swiftc -parse` across all Swift files under `Sources` and `Tests`.
- Swift typecheck of the changed core ownership/backup model dependency set (using a minimal host-only `HelperPolicy` stub for the model's existing Helper wire-model dependency).
- Swift typecheck of `FilterKitBackupService` with the same model dependency set.
- Swift typecheck of `DpkgFileOwnershipProvider` with the same model dependency set.
- Standalone executable smoke test for restore policy:
  - no installed associated App => `skippedNoInstalledAssociation`;
  - Fixed Owner absent but Additional App Association installed => eligible `softAppsMissing`;
  - exact package-managed SHA-256 => `externalDuplicate`;
  - filter disabled => restore preview remains eligible with missing-App warning.
- `Project.yml` YAML parse.
- English and Simplified Chinese localization duplicate-key check: no duplicates.

## Not run / limitations

- Xcode and xcodebuild are not available in this Linux environment; no iOS application build was performed.
- XCTest was not run through Xcode.
- SwiftUI view files were syntax-parsed but not fully typechecked against the iOS SDK.
- No RootHide/ElleKit device validation was performed.
- Actual injection, uninstall, and restore writes remain unavailable; existing production mutation/release gates remain closed.
- APP exact-SHA external duplicate check is currently an inspection/preview guard. The Helper must repeat package ownership and SHA checks immediately before any future mutation to close TOCTOU.
- dpkg ownership detection does not cover non-dpkg package managers; such files remain unknown/read-only unless Helper's trusted FilterKit attestation proves otherwise.
