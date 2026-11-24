# P1-42 Test Report

## Executed

- P1-42 signed-release smoke harness compiled and executed with Swift on Linux: passed.
- Canonical payload signing bytes: passed.
- Modified payload rejected by injected signature checker: passed.
- Unknown key rejected: passed.
- Revoked key rejected: passed.
- Anti-rollback rejects lower generation: passed.
- Same-generation revalidation is idempotent: passed.
- Higher generation accepted: passed.
- Full project Swift syntax parse: passed.
- P1-41 release-trust smoke regression: passed.
- Project configuration verification: passed.
- Architecture verification: passed.
- Localization verification: passed (237 matching zh-Hans/en keys).
- ZIP integrity verification: passed.

## Not executed

- Live `FilterKitHelperRuntime.run()` is not yet switched to the signed-release overload because no production release public key/keyring or signed provisioning artifact has been provisioned. The existing legacy CDHash-only startup path remains in place and must be replaced before a production release.

- Real Ed25519 CryptoKit signature generation/verification on Apple platforms (Linux harness uses a deterministic injected checker).
- Keychain persistence and access-control behavior on iOS/macOS.
- Cross-process anti-rollback race testing on Darwin.
- Xcode/iOS build and XCTest execution.
- RootHide/Rootless device validation.
- Apple certificate chain, revocation, notarization, or release publisher authority verification.
- Real Root Installer deployment or launchd operations.

All real deployment gates remain closed. No jailbreak filesystem or launchd state was modified.
