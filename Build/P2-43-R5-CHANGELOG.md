# P2-43-R5 — IPC Client Code-Signing Identity Binding

## Scope

Bind the Helper's authenticated IPC peer to the installed FilterKit App's signed code identity. A caller-provided Bundle ID is never accepted as identity evidence. CDHash, Bundle ID/signing identifier, and Team ID remain distinct facts.

## Changes

1. `HelperPeerIdentity` now carries `verifiedCodeIdentifier` and `verifiedTeamIdentifier`. These fields are populated only by the platform peer-identity provider; they are not decoded from an IPC request payload.
2. `DarwinPeerIdentityProvider` uses the socket's kernel `LOCAL_PEERTOKEN` snapshot to create a `SecTask` through `SecTaskCreateWithAuditToken`, then reads the task's signing identifier through `SecTaskCopySigningIdentifier` and Team ID through the signed `com.apple.developer.team-identifier` entitlement. Missing values fail closed.
3. `HelperTrustPinSet` and the root-owned `HelperDeploymentManifest` carry the expected Bundle ID and Team ID. The installer provisioning model accepts Team ID only as signing-pipeline input; it does not derive it from CDHash or user IPC.
4. `HelperTrustConfigurationValidator` rejects legacy/incomplete production manifests without both identity pins before the Helper opens its socket.
5. `HelperPeerTrustPolicy` requires exact CDHash pin, expected UID/GID, signed identifier, and Team ID when production identity pins are configured.
6. `HelperPolicy.authorize` independently rechecks the signed identifier and Team ID before deployment authorization.
7. Added pure identity comparison tests, provisioning tests, host smoke harness, and static audit.

## Security semantics

- CDHash is a hash of a code directory; it is not a Bundle ID or Team ID.
- The signing identifier is OS-observed from the task represented by the socket audit token. It is compared case-insensitively to the installer-pinned Bundle ID.
- Team ID is read from the task's signed Team ID entitlement and compared exactly to the installer-pinned Team ID.
- The Helper does not trust a Bundle ID supplied in a request, nor infer one from PID, UID, GID, CDHash, or socket path.
- A new build may have a different CDHash. Team ID + signing identifier provide the stable developer/app identity dimensions; exact CDHash pin rotation still requires a trusted installer update.
- Reinstall continuity is conditional on the same signing identifier and Team ID. Reinstalling under a different team is rejected. No automatic migration or pin refresh is introduced.
- Designated Requirement extraction/evaluation is not added in this phase; it remains a possible future strengthening, not an assumed property.

## Platform/API boundary

The Darwin implementation uses Apple's Security task APIs with the audit token from the connected socket. Apple documents `SecTaskCreateWithAuditToken`, `SecTaskCopySigningIdentifier`, and `SecTaskCopyValueForEntitlement`; the implementation still requires compilation against the project's actual iOS SDK and runtime verification on the supported RootHide jailbreak. Linux host tests cannot validate the Darwin ABI, entitlement availability, or audit-token behavior on-device.

If the App is ad-hoc signed or the Team ID entitlement is unavailable, identity acquisition fails and the Helper rejects the connection. This is intentional fail-closed behavior.

## Validation performed

- Swift 6.2.1 Linux syntax parse: 247/247 Swift source and test files passed.
- Host identity comparison smoke: 4/4 passed (matching identity accepted; wrong Bundle ID, wrong Team ID, and absent OS evidence rejected).
- Prior R4/R3/R2/R1/R24 audits: 11/11, 14/14, 14/14, 12/12, and 12/12 passed respectively.
- `Project.yml` YAML parse passed; English and Simplified Chinese localizations both contain 519 unique keys with identical key sets.
- Static R5 boundary audit: 13/13 assertions passed.
- Full Xcode/iOS/Helper build, XCTest, Darwin Security framework typecheck, socket integration, signed installer generation, and RootHide/ElleKit device acceptance were not run in this Linux environment.
- All production deployment/association/uninstall write gates remain closed.
