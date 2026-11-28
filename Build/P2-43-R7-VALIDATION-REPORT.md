# P2-43-R7 Validation Report

## Baseline

- Input: `FilterKit-P2-43-R6-Source.zip`
- SHA-256: `cfb051beeb26b566d51853925fd5a2b2a6273d4d620bd285c0f869222adab186`
- `unzip -t`: passed before extraction.
- Worktree: fresh `/mnt/data/FilterKit-P2-43-R7-Work/FilterKit-P2-42`; R6 archive was not modified.

## Actual source changes

- Added signed provisioning envelope and Ed25519 verifier.
- Runtime loader now requires and verifies `provisioning.signed.json` before using App/Helper identity pins; unsigned `provisioning.json` is no longer a fallback.
- Journal chain validation now also verifies legal event-to-state transitions.
- Added `HelperSignedProvisioningManifestTests.swift`, host smoke harness, static audit, changelog and this report.

## Executed validation

- Swift syntax parse: 251/251 source and test files passed.
- R7 signed-provisioning static audit: 9/9 passed.
- R7 host smoke: 4/4 passed (canonical payload encoding, revoked key rejection, generation window enforcement, unsupported algorithm rejection).
- R6 identity-rotation audit: 15/15 passed.
- Project.yml YAML parse: passed.
- Localization: English and Simplified Chinese each contain 519 unique keys; key sets are identical.

## Not executed

- No Xcode/iOS SDK build or XCTest run.
- No real Ed25519 signed provisioning artifact was produced or verified; the host smoke uses an `AcceptAll` test checker and proves policy wiring only.
- No privileged root-owned writer for `provisioning.signed.json` was implemented or exercised.
- No durable provisioning-baseline history, generation-digest equivocation ledger, or hardware monotonic counter was added.
- No Darwin Keychain, filesystem no-follow, launchd, App upgrade/reinstall, repin transaction, or RootHide/ElleKit device acceptance was run.

## Release posture

All production write and installer execution gates remain closed. Existing deployments with only unsigned `provisioning.json` will fail closed until a trusted installer provisions `provisioning.signed.json`. R7 is source-level provenance enforcement plus host policy validation, not production release certification.
