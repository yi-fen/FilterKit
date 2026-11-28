# P2-43-R7 — Signed Provisioning Provenance & Recovery Validation

## Changes

1. Added `HelperSignedProvisioningManifest`, an Ed25519 signed envelope whose canonical sorted-key JSON payload is the complete `HelperInstallerProvisioningBundle` (including App CDHash, Bundle ID, Team ID, Helper CDHash, UID, jailbreak root, socket and route paths, release identifier, and generation).
2. Added `HelperProvisioningSignatureVerifier`. It rejects malformed envelopes, unsupported algorithms, invalid/duplicate signing-key sets, revoked/unknown keys, invalid public keys/signatures, and signing keys outside their authorized generation window.
3. Changed `HelperSignedReleaseRuntimeLoader` to read `provisioning.signed.json`, verify its signature against the configured release trust anchors, and only then consume its payload. The previous unsigned `provisioning.json` path is no longer accepted.
4. Strengthened `HelperInstallerTransactionJournal.validateChain()` to validate each event's legal state transition as well as sequence, prior-state, hash-chain, and final-state consistency. This prevents a journal with recomputed hashes but impossible event ordering from being accepted as a valid recovery history.
5. Added XCTest source, a host smoke harness, and a static audit for the signed provisioning path.

## Compatibility / deployment impact

Existing installations containing only `provisioning.json` will now fail closed during Helper runtime preflight. A trusted installer/release pipeline must generate `provisioning.signed.json` after final App and Helper signing, sign the exact canonical payload with an authorized release key, and install it as a root-owned mode-0600 regular file. This phase does not implement that privileged writer or produce a real release signature.

## Security boundary

- The signature authenticates provisioning content; root-owned no-follow file reading remains required to protect the on-device artifact.
- CDHash remains a version-specific pin; Bundle ID and Team ID remain distinct signed identity fields.
- A signature verifier using a test `AcceptAll` checker is only a host policy harness, not cryptographic verification evidence.
- The existing Keychain generation ledger remains the device anti-rollback mechanism. This phase does not create a hardware monotonic counter or a root-owned append-only provisioning-history database.
- The repin dry-run remains non-writing. No privileged installer, repin transaction, or production mutation gate is enabled.
