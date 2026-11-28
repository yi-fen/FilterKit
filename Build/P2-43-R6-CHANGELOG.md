# P2-43-R6 — Client Identity Rotation and Helper Self-Identity Repair

## Scope

R6 hardens the trusted installer repin path and repairs a startup regression in the R5 Darwin peer identity provider. It does not enable production writes.

## Changes

1. **Repair Helper self-CDHash lookup.** R5's `ownCDHash()` delegated to the peer identity method without a connected socket. That method correctly requires a kernel `LOCAL_PEERTOKEN` to establish a client identity, so the self-lookup could never produce a signed peer identity and Helper startup would fail. `ownCDHash()` now reads only the current Helper process CDHash through `csops(getpid(), CS_OPS_CDHASH, ...)`, independently of client peer authentication.
2. **Keep peer identity bound to the socket.** Client identity acquisition still reads `LOCAL_PEERTOKEN` before and after the CDHash lookup, checks its credential tuple against `getpeereid`/peer credentials, and obtains signing identifier + Team ID from a `SecTask` created from the complete audit token. A missing token remains a hard failure for peer identity.
3. **Add App CDHash rotation policy.** `HelperClientCodeIdentityRotationPolicy` accepts only an installer-provisioned transition with exactly one generation increment, unchanged Bundle ID, unchanged Team ID, unchanged client UID/socket group, unchanged jailbreak root and paths, unchanged Helper CDHash, and a genuinely changed valid App CDHash.
4. **Wire rotation checks into installer dry-run.** `.repin` now requires a previous provisioning record. Missing baseline or an invalid identity transition fails closed. The dry-run remains non-writing and returns `executionEnabled == false`.
5. **Add tests and audits.** Added XCTest coverage for accepted rotation, generation rollback/replay, Bundle ID/Team ID changes, Helper pin changes, malformed/no-op rotations, and dry-run baseline requirements. Added a host smoke harness and static boundary audit.

## Security boundaries / limitations

- The previous provisioning record must come from the authenticated root-owned release/provisioning state. This policy is not safe if an untrusted caller can supply both `previous` and `next` values.
- R6 does not implement automatic pin refresh, persistent anti-rollback storage, or execute the repin transaction. The existing installer execution gate remains closed.
- R6 does not add designated-requirement evaluation. The current R5 `SecTask` signing identifier + Team ID checks remain the runtime identity evidence. A future designated-requirement implementation must first establish API availability and semantics for the actual iOS/jailbreak deployment target; macOS `SecCode` behavior must not be assumed to exist on iOS.
- Linux cannot typecheck Darwin `csops`, `LOCAL_PEERTOKEN`, `SecTask`, or Security framework ABI behavior against an iOS SDK.

## Validation

- Swift 6.2.1 Linux syntax parse: 249/249 source and test files passed.
- R6 host rotation smoke: 5/5 assertions passed.
- R6 static identity/repin audit: 15/15 assertions passed.
- R5 code identity binding audit: 13/13 passed.
- Retained lifecycle/boundary audits: R1 12/12, R2 14/14, R3 14/14, R4 11/11.
- Project.yml YAML parse passed.
- English and Simplified Chinese localizations: 519 unique keys each; key sets identical.
- XCTest execution, Xcode/iOS SDK build, Darwin API typecheck, signed-artifact test, socket integration, and RootHide/ElleKit device acceptance were not run.

## Release posture

All production deployment, injection, activation, association, restore, uninstall, and installer execution gates remain closed.
