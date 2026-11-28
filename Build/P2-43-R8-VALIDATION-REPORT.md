# P2-43-R8 Validation Report

## Base archive

- Input: `FilterKit-P2-43-R7-Source.zip`
- SHA-256: `e9f676da8cf0b38ce751e117f03c5b26f0cc99f79e065033d49365b83fde7632`
- `unzip -t`: passed before extraction.
- Worktree: fresh `FilterKit-P2-43-R8-Work/FilterKit-P2-42`; R7 archive and prior worktree were not modified.

## Executed checks

- Swift 6.2.1 Linux.
- Swift frontend parse over all app/helper/source/test Swift files: 256/256 passed.
- R8 host smoke compiled the real Provisioning model, signed-envelope verifier model, identity-rotation policy, trusted store, and SHA-256 implementation with narrow platform/model stubs: 13/13 assertions passed. Coverage includes atomic POSIX write/read/replace, signed baseline acceptance, Repin rotation, same-generation digest conflict, interrupted checkpoint recovery, and Bundle ID case normalization.
- R8 selected-source Swift typecheck with narrow dependency stubs: passed.
- R8 static audit: 16/16 passed.
- R7 signed-provisioning audit: 10/10 passed.
- R6 identity-rotation audit: 15/15 passed.
- R5 identity-binding audit: 13/13 passed.
- R4 APP/Plugin boundary audit: 11/11 passed.
- R3 first-install binding audit: 14/14 passed.
- R2 lifecycle integration audit: 14/14 passed.
- R1 backup lifecycle audit: 12/12 passed.
- R24 lifecycle audit: 12/12 passed.
- Project.yml YAML parse: passed.
- English and Simplified Chinese localization: 519 unique keys each, key sets identical.

## Not executed / not claimed

- No Xcode, Apple iOS SDK, `xcodebuild`, or XCTest execution in this Linux environment.
- `Security` / Keychain implementation is syntax-parsed but not compiled or exercised against Apple Security.framework here.
- The POSIX Root-owned file store was typechecked and exercised against a temporary root-owned 0700 Linux directory, but not run against a real jailbreak filesystem hierarchy or Darwin filesystem semantics.
- The Ed25519 Host Smoke uses an injected accept-all checker for control-flow testing; it is not cryptographic signature verification. Real Ed25519 remains delegated to CryptoKit on Apple platforms.
- No privileged installer creates the 0700 directory, provisions Keychain checkpoints, or performs production Repin writes.
- No RootHide / ElleKit device acceptance, App upgrade/reinstall continuity test, launchd transaction, or real Helper startup test.

All production installer and plugin mutation gates remain closed.
