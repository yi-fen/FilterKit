# P1-40 Test Report

## Executed

- Full project Swift syntax parse across `Sources`, `App`, `HelperRuntime`, and `Tests/UnitTests`: passed.
- P1-40 portable source type-check and executable smoke harness: passed. The harness compiles the actual `HelperCodeSignatureVerifier.swift` and `HelperRuntimePreflight.swift`; minimal manifest/policy/recovery fixtures isolate the portable logic from platform services.
- P1-40 smoke cases: matching CDHash accepted; mismatched and empty pins rejected; clean preflight reported; pending journal reported without mutation and blocks the preflight's deployment predicate; mismatched running identity rejected.
- P1-39 three-artifact activation and fault-injection regression smoke: passed.
- Project configuration verification: passed.
- Architecture structure verification: passed.
- Localization verification: passed (237 matching zh-Hans/en keys).
- ZIP integrity verification: passed.

## Not executed

- Xcode/iOS build or XCTest.
- macOS Security.framework static-code verification or compilation of the macOS-only branch.
- iOS/XNU `csops(CS_OPS_CDHASH)` runtime verification.
- RootHide/Rootless device testing, launchd operations, or live installation.
- Apple Team ID, certificate-chain, notarization, or publisher-provenance validation.

No live jailbreak paths were touched. All real deployment gates remain closed.
