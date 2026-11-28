# P2-43-R9 Validation Report

## Base archive

- Input: `FilterKit-P2-43-R8-Source.zip`
- SHA-256: `ae2edddba74884ec4b7fe71cf04d903b9b3abc3251b87633f79a92165931dca5`
- `unzip -t`: passed before extraction.
- Worktree: fresh `FilterKit-P2-43-R9-Work/FilterKit-P2-42`; R8 archive and previous worktrees were not modified.

## Executed checks

- Swift 6.2.1, Linux x86_64.
- Swift frontend parse over all app/helper/source/test Swift files: 312/312 passed.
- Selected-source Swift typecheck for the new coordinator and release-set implementation against narrow dependency stubs: passed. This validates those source files' type relationships against the stubbed contracts, not a full app/helper target build.
- R9 release-manifest Host Smoke: 5/5 passed. It compiled the real `HelperRootReleaseSet.swift` and real `SHA256Digest.swift` with narrow model/policy stubs. One matching release passed; mismatched Team ID, App CDHash, missing Team ID, and execution-enabled manifest were rejected.
- R9 trusted-installer boundary audit: 18/18 passed.
- R8 trusted Provisioning audit: 16/16 passed.
- R7 signed Provisioning audit: 10/10 passed.
- R6 identity rotation audit: 15/15 passed.
- R5 identity binding audit: 13/13 passed.
- R4 APP/Plugin boundary audit: 11/11 passed.
- R3 first-install binding audit: 14/14 passed.
- R2 lifecycle integration audit: 14/14 passed.
- R1 backup lifecycle audit: 12/12 passed.
- Project.yml YAML parse: passed.
- English and Simplified Chinese localization: 519 unique keys each, key sets identical.
- `unzip -t` and SHA-256 of the generated R9 archive: recorded after packaging.

## Not executed / not claimed

- No Xcode, Apple iOS SDK, `xcodebuild`, or XCTest execution in this Linux environment.
- Darwin `flock` behavior and RootHide filesystem semantics were not device-tested.
- The R9 adapter protocol has no production implementation. No privileged filesystem operation, Keychain write, launchd operation, Helper install/upgrade/Repin, or plugin mutation was executed.
- R9's signature preflight path was not tested with a production Ed25519 signature. The Host smoke exercised release-manifest identity checks, not Ed25519 cryptographic acceptance.
- The selected-source typecheck used narrow stubs for unrelated model/platform dependencies; it is not equivalent to full target typechecking.
- No RootHide / ElleKit device acceptance or crash-injection test was run.

All production Helper installation and plugin mutation gates remain closed.
