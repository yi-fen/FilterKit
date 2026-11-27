# P2-37-R3 — APP Activation Authorization Preflight & State Consistency

## Baseline

- Input: `FilterKit-P2-37-R2-Helper-Identity-Attestation.zip`
- Input SHA-256: `2c11dc686974c6759f315fc745dd6a5b242643a20d002e941aed0a4ec340f147`
- This R3 worktree was extracted from that archive before changes.

## Changes

1. **Manifest identity is now tied to the exact scanned bytes.** `ReadOnlyPluginScanner` reads the manifest payload once, computes its SHA-256 from those bytes, and decodes the association projection from the same payload. It records file size, modification time, and filesystem file number for dylib, plist, and manifest. The scanner compares metadata before and after reading each file; a concurrent replacement makes that observation unusable.
2. **Helper evidence has an explicit freshness window.** `HelperPluginIdentityAttestation.maximumAge` is 120 seconds. A future-dated response beyond the small clock-skew allowance or an expired response cannot authorize even a preview.
3. **Complete association-set consistency is checked.** The App-side identity resolver compares Helper's complete soft-association set with the scan projection and checks it against `Filter.Bundles`: enabled soft associations must be present, disabled soft associations must be absent, and undeclared bundle targets are rejected. Global filters and Classes/Executables matching remain non-attributable and locked.
4. **Ownership handling is explicit.** Package-manager-owned plugins are rejected. The scanner intentionally reports ownership as unknown; that state remains read-only until a fresh Helper root-side attestation proves the FilterKit manifest/payload ownership conditions. A manifest UUID by itself is not sufficient.
5. **File-change and expiry invalidation are automatic.** `PluginScanRegistry` checks the captured file observations every five seconds. A changed/missing artifact immediately clears Helper evidence, increments the scan revision (which clears pending per-App previews), and starts a new read-only scan. Expired attestations do the same. Definitive Helper rejection is retained (not blindly retried); transient Helper-unavailable results are retried at a bounded 30-second interval.
6. **Hard-bound and soft-associated App state remains independent.** Hard binding remains immutable, but the hard-bound App's `Filter.Bundles` membership can be off. Each `(Plugin ID, target Bundle ID)` preview remains isolated.
7. **No mutation path was added.** APP detail switches still update only the local preview ledger. No Filter.plist/Manifest write, Helper mutation request, or injection operation is called.
8. Added English and Simplified Chinese copy for expired Helper identity evidence and added regression coverage.

## Files of note

- `Sources/Core/Models/PluginScanModels.swift`
- `Sources/Core/Models/Helper/HelperPluginIdentityAttestationModels.swift`
- `Sources/Core/Models/PluginIdentityVerificationResult.swift`
- `Sources/Environment/ReadOnlyPluginScanner.swift`
- `Sources/Environment/PluginScanRegistry.swift`
- `Sources/Environment/Deployment/AppPluginActivationStateResolver.swift`
- `Tests/UnitTests/AppPluginActivationStateResolverTests.swift`
- `Build/Host/P2-37-R3-Activation-Consistency-Smoke.swift`
- `Build/Host/run-p237r3-activation-consistency-smoke.sh`
- `Build/scripts/p237r3_activation_consistency_audit.py`
