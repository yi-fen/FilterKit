# P1-43 — Signed Trust Runtime Integration & Key Rotation

## Implemented

- The production `FilterKitHelperRuntime.run()` path no longer calls the legacy unsigned/CDHash-only preflight. Before opening the IPC listener it calls `HelperSignedReleaseRuntimeLoader`.
- The loader requires a non-empty compile-time `HelperReleaseTrustAnchors.keys` keyring; the checked-in default is intentionally empty and therefore fails closed until a release build provisions reviewed public keys.
- Reads `release.signed.json` and `provisioning.signed.json` from `JBROOT/Library/FilterKit/Helper` using the existing root-owned, no-follow reader. Both must be root:root regular files with mode `0600`.
- Verifies the signed Ed25519 envelope with CryptoKit on Apple platforms, validates release/provisioning/JBROOT/path binding, hashes the current executable image, compares its CDHash, and performs the existing read-only journal recovery assessment.
- Persists accepted Generation through the Apple Keychain implementation. Non-Apple platforms have no production fallback and fail closed.
- Serializes signed release acceptance with the same persistent `.filterkit-root-activation.lock` inode used by the multi-file activation executor. It does not create or unlink the lock; missing/unsafe/busy lock state fails closed.
- Key rotation now supports explicit generation windows. Retired keys require a maximum generation; active keys cannot have a maximum generation; retired generation ceilings must sit below the earliest configured active-key generation; duplicate IDs, overlapping windows, invalid bounds, and invalid key IDs are rejected. Revoked keys remain rejected.
- Added `configure-helper-release-keys.py` to generate the compile-time Swift trust-anchor file from an offline-reviewed JSON keyring. It validates 32-byte Ed25519 public keys, unique IDs, lifecycle status, generation bounds, and presence of an active key. Private keys are never accepted by this script.

## Runtime artifact contract

The root-owned Helper directory must contain:

- `release.signed.json` — signed envelope, root:root `0600`.
- `provisioning.signed.json` — signed installer provisioning envelope, root:root `0600`.
- `manifest.json` — existing deployment manifest, root:root `0600`.

The signed payload's release identifier, generation, bundle ID, Helper version and CDHash must agree with the provisioning bundle; the provisioning JBROOT and deployment paths must agree with the loaded deployment manifest. The running executable's SHA-256 and kernel-reported CDHash are checked against the signed payload.

## P2-43-R8 persistence update

P2-43-R8 supersedes the original P1-43 Provisioning read path with `HelperTrustedProvisioningStore`. It requires the pre-created Helper directory to be root:root `0700`, atomically writes the signed envelope through a fixed-leaf no-follow file store, records an append-only generation + exact-envelope-digest checkpoint in device-local Keychain, and reconciles `provisioning.pending.json` after interrupted replacement. Repin baselines are emitted only after signature and checkpoint validation. This does not add the privileged installer writer; production installation/repin remains gated.

## Key rotation procedure

1. Add the new public key as `active` with its first authorized `minimumGeneration`.
2. Mark the previous key `retired` and set its final authorized `maximumGeneration`.
3. Ship the updated trust-anchor source in a trusted Helper build.
4. Sign subsequent release manifests with the new private key.
5. To revoke a key, set its status to `revoked` in a trusted update. A revoked key cannot verify releases.

The generator input schema is `{ "schemaVersion": 1, "keys": [{ "identifier", "status", "publicKeyBase64", "minimumGeneration", "maximumGeneration" }] }`. Omit optional generation bounds with JSON `null`.

## Security boundaries / not claimed

- The checked-in trust-anchor list is empty because no production release public key was provided. The live runtime therefore intentionally cannot start until a real reviewed public keyring is generated and compiled in.
- Keychain is device-local persistence, not a hardware monotonic counter. A privileged jailbreak attacker or full-device rollback can defeat this class of anti-rollback state.
- `integrityOnly` authenticates the signed release's byte identity; it does not prove an Apple Team ID. `pinnedAppleIdentity` remains fail-closed unless real publisher observations are supplied; this runtime integration currently passes no Team ID/certificate observation.
- Linux smoke tests use a deterministic signature-checking test double. They do not exercise CryptoKit Ed25519, Apple Keychain, Darwin `flock`, `csops`, or actual iOS launch behavior.
- Root Installer execution remains disabled. No launchd bootstrap/bootout or jailbreak filesystem deployment was performed.

## Validation

See `TEST-REPORT-P1-43.md` for the commands and actual results.
