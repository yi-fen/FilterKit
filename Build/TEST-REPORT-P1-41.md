# P1-41 Test Report

## Executed

- Full project Swift syntax parse across `Sources`, `App`, `HelperRuntime`, and `Tests/UnitTests`: passed.
- P1-41 portable typecheck and executable smoke harness using the actual release trust model and verifier sources: passed.
- Matching release/provisioning identity accepted: passed.
- Helper SHA-256 mismatch rejected: passed.
- Running CDHash mismatch rejected: passed.
- Incomplete publisher pins rejected: passed.
- Team ID mismatch rejected: passed.
- Missing publisher observations rejected: passed.
- Release extraction shell script syntax (`bash -n`): passed.
- Project configuration verification: passed.
- Architecture structure verification: passed.
- Localization verification: passed (237 matching zh-Hans/en keys).

## Not executed

- XCTest execution (no Xcode/iOS SDK in this environment).
- macOS `codesign` extraction against a real signed Helper.
- Apple certificate-chain, revocation, notarization or publisher-authority verification.
- Runtime executable SHA-256 / Team ID / certificate acquisition on iOS/RootHide.
- Xcode/iOS build, RootHide/Rootless device test, live installation or launchd operations.

All real deployment gates remain closed. No jailbreak filesystem or launchd state was modified.
