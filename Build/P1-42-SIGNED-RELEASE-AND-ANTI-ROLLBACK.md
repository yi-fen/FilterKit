# P1-42 — Signed Release Manifest & Anti-Rollback Protection

## Added

- `HelperSignedReleaseManifest`: versioned envelope, fixed `Ed25519` algorithm identifier, key identifier, canonical payload bytes (`JSONEncoder` sorted keys), and strict 64-byte signature decoding.
- `HelperReleaseSignatureVerifier`: trusted-key allowlist, 32-byte raw Ed25519 public keys, unknown/revoked-key rejection, and CryptoKit-backed signature verification on Apple platforms. Private signing keys are not included in FilterKit.
- `Build/Scripts/sign-helper-release-manifest.swift`: macOS release-side signing utility. It reads a 32-byte raw private key from `FILTERKIT_RELEASE_ED25519_PRIVATE_KEY_BASE64`, signs the canonical payload, writes the signed envelope, and prints the corresponding public key for trust-root provisioning. The private key must remain in the release signing system and must never be committed to the repository.
- Key rotation policy: multiple key IDs may coexist in the embedded trust list; active and retired keys can verify already-issued releases, while revoked keys are rejected. Changing the trust list/revocation status requires a trusted app/Helper update in this phase; there is no remotely mutable keyring.
- `HelperReleaseAntiRollbackGuard`: checks the highest accepted release generation and records a generation only after signature, release identity, Helper digest/CDHash, and startup inspection succeed.
- `KeychainHelperReleaseGenerationStore`: device-local Keychain persistence using `AfterFirstUnlockThisDeviceOnly`; in-memory implementation is test-only.
- Signed-release HelperRuntime preflight overload. Signature verification and anti-rollback checks precede trusting release pins. Existing unsigned P1-41 overload remains for compatibility. The current `FilterKitHelperRuntime.run()` call site still uses the legacy CDHash-only overload; switching it to the signed overload is intentionally pending a real release public key/keyring and signed provisioning artifacts. Therefore P1-42 provides the signed gate API but does not yet make signed release verification mandatory in the live runtime.

## Security boundaries

- Ed25519 is implemented with CryptoKit on Apple platforms. The Linux smoke harness uses a deterministic injected test checker; it does **not** exercise real Ed25519 cryptography.
- The Keychain generation record is a device-local rollback barrier for ordinary app-level state changes, not a hardware monotonic counter. It cannot defeat a privileged jailbreak attacker, a compromised trust root, full device-state restoration, or replacement of the Helper itself.
- Keychain read/compare/write is serialized within this process. Production wiring must also serialize startup acceptance across Helper processes using the existing shared activation lock. It is not a Secure Enclave monotonic counter.
- Rotation/revocation is currently provisioned by a trusted software update (embedded allowlist), not by an online root-signed keyring update protocol.
- `integrityOnly` remains a digest identity policy; publisher identity requires the existing `pinnedAppleIdentity` observations.
- Real installer execution remains disabled. This stage does not activate launchd or modify jailbreak files.

## Validation

The portable smoke harness exercises canonical payload binding, tamper rejection, unknown/revoked key rejection, and generation monotonicity using a deterministic test checker. Full Apple-platform CryptoKit, Keychain, Xcode, XCTest, and RootHide device validation remain outstanding.
