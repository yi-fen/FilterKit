# P1-44 — Apple Platform Verification & Release Provisioning Gate

## Scope

P1-44 adds Apple-native verification tests and tightens persistent anti-rollback storage. It does **not** claim an Apple build or device test was run in the Linux development environment.

## Changes

- Added an RFC 8032 Ed25519 known-answer test using the real `HelperEd25519SignatureChecker`/CryptoKit implementation when CryptoKit is available. It verifies the valid empty-message vector and rejects a modified signature and modified message.
- Added Security.framework Keychain tests for persistence across store instances, rollback rejection, and concurrent writers.
- Changed the Keychain generation store from a mutable singleton value to an append-only per-generation ledger. Distinct Keychain item additions are atomic; concurrent processes cannot overwrite a higher generation with a stale lower value. The previous singleton account is read as a migration floor. This remains device-local state, not a hardware monotonic counter.
- Added `Build/Scripts/run-apple-platform-tests.sh`, which requires macOS, XcodeGen, Xcode, and an explicit simulator destination before running the `FilterKit` XCTest scheme.
- Added `Build/Scripts/verify-helper-release-provisioning.py` to audit generated compile-time trust anchors for non-empty active key set, unique IDs, valid 32-byte Ed25519 public keys, and non-overlapping generation windows.

## Running Apple tests

```sh
FILTERKIT_TEST_DESTINATION='platform=iOS Simulator,id=<SIMULATOR-UDID>' \
  Build/Scripts/run-apple-platform-tests.sh
```

The script generates the Xcode project under `Build/Generated/` and runs XCTest. The simulator UDID must be selected from the local Xcode installation.

## Release provisioning gate

After reviewing an offline release keyring and generating the trust-anchor source:

```sh
python3 Build/Scripts/configure-helper-release-keys.py reviewed-keyring.json \
  Sources/Environment/Helper/Runtime/HelperReleaseTrustAnchors.swift
python3 Build/Scripts/verify-helper-release-provisioning.py \
  Sources/Environment/Helper/Runtime/HelperReleaseTrustAnchors.swift
```

The audit only checks trust-anchor structure; it does not inspect a release payload's publisher policy, cryptographically validate a signed release envelope, or validate an Apple certificate chain. The checked-in project intentionally retains an empty keyring because no production public key was supplied. Consequently, production Helper startup remains fail-closed until a reviewed keyring is provisioned.

## Not performed here

- Xcode/iOS Simulator build or XCTest execution (this environment is Linux).
- Real CryptoKit or Keychain execution.
- Apple certificate-chain/revocation verification or notarization.
- RootHide/Rootless device testing, launchd operations, or real installation.

`executionEnabled` remains false. No jailbreak files or launchd jobs were modified.
