# P2-37-R2 — Helper Plugin Identity Attestation

## Scope

P2-37-R2 connects APP-detail activation preview eligibility to a read-only identity attestation produced by the authenticated Helper. It does not add or release an activation mutation path.

## Changes

- Added `HelperPluginIdentityAttestationRequest` and `HelperPluginIdentityAttestation` IPC models.
- Added versioned IPC message types for identity attestation request/response.
- Added a Helper-side read-only attestor that requires root, resolves dpkg package ownership, verifies the root-owned schema-3 manifest, checks exact dylib/plist SHA-256 values, verifies the Mach-O identity fingerprint, and returns a bounded Filter projection.
- Extended `HelperOwnershipProof` with the verified manifest association and parsed Filter projection produced from the same verified file reads.
- Routed attestation requests through `HelperRequestDispatcher`, with request-ID/time validation, clean-recovery requirement, and mandatory audit append.
- Wired the production Helper runtime to the configured plugin directory and dpkg info directories.
- Added an App-side read-only attestation client. The scan registry sends the manifest UUID only as an untrusted lookup hint and attaches only Helper-authored responses.
- Changed activation identity resolution to require a fresh Helper attestation and compare plugin ID, filenames, local payload hashes, Mach-O fingerprint, hard binding, soft association states, and Filter projection.
- Split `PluginManagementPermission` out of `PluginFilterConfiguration.swift` so the Helper target can compile the shared read-only Filter parser without importing App-only scanner permission types.
- Added English and Simplified Chinese explanations for missing or mismatched Helper attestation.

## Safety

- Attestation is read-only. The Helper attestor has no write, rename, chmod, or delete path.
- No App-supplied paths, file bytes, hashes, or ownership assertions are trusted by Helper.
- A package-owned, malformed, stale, mismatched, ambiguous, or unverifiable plugin remains read-only.
- Attestations expire for activation-preview eligibility after 120 seconds.
- App, coordinator, Helper association commit, and activation mutation release gates remain closed.
