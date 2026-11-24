# P1-43 Test Report

## Executed

- Full Swift syntax parse across `Sources`, `App`, `HelperRuntime`, and `Tests/UnitTests`: PASS.
- HelperRuntime + Core Helper models + Runtime + Execution + Installer Linux Swift typecheck: PASS. Apple-only Security/Keychain and Darwin code paths are conditionally excluded on Linux.
- P1-43 signed-release smoke test: PASS.
  - Canonical signed payload and tamper rejection.
  - Unknown and revoked key rejection.
  - Anti-rollback monotonicity and idempotent same-generation check.
  - Retired-key generation ceiling and new active-key lower bound.
  - Duplicate key IDs rejected.
  - Overlapping retired/active key-generation windows rejected by the keyring generator.
  - The signature checker is a deterministic test double, not Ed25519.
- Release key generator Python syntax: PASS.
- Release key generator valid-keyring output, invalid-retired-key rejection, and overlapping-generation-window rejection: PASS.
- Generated trust-anchor Swift source parse and typecheck against the complete HelperRuntime source set: PASS (using temporary test keys, not shipped in the project).
- Project configuration verification: PASS.
- Architecture verification: PASS.
- Localization verification: PASS (237 matching zh-Hans/en keys).
- ZIP integrity: PASS.

## Not executed

- Xcode/iOS/Darwin build or XCTest.
- CryptoKit Ed25519 cryptographic execution.
- Apple Keychain persistence and cross-process behavior on device.
- Darwin `flock`, `csops`, and executable-path/file-mode behavior on RootHide.
- RootHide/Rootless device tests, launchd operations, or real installation.
- Production trust-anchor provisioning: no real release public key was supplied. The checked-in trust anchor list is empty, and the runtime correctly fails closed until a trusted release build provisions it.

## Safety state

`executionEnabled` remains false. No jailbreak files were installed, replaced, removed, or modified. No launchd job was started or stopped.
