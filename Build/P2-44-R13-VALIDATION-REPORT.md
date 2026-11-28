# P2-44-R13 Validation Report

## R13 dedicated results

- Prepared Activation static audit: **23/23**.
- Prepared Activation Host integration smoke: **10/10**.

The Host smoke compiles the actual source files:
- `Sources/Environment/Helper/Runtime/HelperTrustedInstallerCoordinator.swift`
- `Sources/Environment/Helper/Execution/HelperRootAtomicActivationExecutor.swift`
- `Sources/Environment/Helper/Runtime/HelperInstallerActiveReleasePointerWriter.swift`
- `Sources/Environment/SHA256Digest.swift`

The test reaches `Coordinator.prepare()` and then the formal `activate(... prepared:)` overload in the same process. It checks:
1. Invalid deterministic test signature is rejected.
2. `prepare()` returns the immutable Prepared value.
3. Exact provisioning-envelope bytes are bound by SHA-256.
4. Stale Observer challenge is rejected before Active mutation.
5. Tampered staged bytes are rejected before Active mutation.
6. Formal prepared activation uses the Prepared transaction ID.
7. Durable Journal fixture reaches `activated`.
8. Active Pointer binds Transaction ID, Release ID, and Generation.
9. Pointer hashes match all three independently observed Active files.
10. Active executable bytes match the prepared release.

**Important:** Journal persistence, signature verification, staged-store loading, and Observer identity are narrow Host test adapters. This is not evidence that the production Durable Journal Store, production R7 Staged Store, Darwin Observer, or real Ed25519 verifier have passed end-to-end execution. Previous Release / upgrade activation and prepared-path crash Recovery remain untested in this R13 smoke.

## Historical regressions run

- R5 Active Transaction Host smoke: **13/13**.
- R8 Staged / Previous filesystem Host smoke: **25/25**.
- R9 activation chain Host smoke: completed successfully.
- P2-44 R1–R12 validation chain: completed successfully through `run_p244_r12_validation.sh`.
- P2-43 historical crash recovery, descriptor filesystem, recovery, preflight, security, and dry-run smokes completed; recorded results include R11 17/17, R12 18/18, R13 13/13, R14 14/14, and R16 21 assertions.

## Project checks

- Swift syntax parse: **274/274 Swift files** passed.
- `Project.yml` YAML parse: passed.
- English localization: **519 unique keys**.
- Simplified Chinese localization: **519 unique keys**.
- Localization key parity: passed.

## Platform boundary

Environment: Linux Swift 6.2.1. No Xcode, Apple SDK, `xcodebuild`, XCTest, Darwin `flock`/launchd/XPC, RootHide/ElleKit device acceptance, or real power-loss/kernel-crash testing was available. The Host run does not substitute for those checks.

**Production write gates remain closed.**
