# P2-13 — Darwin Peer Authentication & RootHide Validation

## Scope

P2-13 tightens the identity policy at the AF_UNIX boundary. It does not claim that Darwin syscalls or a RootHide device have been exercised in this build environment. No plugin configuration is written and all execution release gates remain closed.

## Changes

1. `HelperPeerTrustPolicy` can enforce an explicit GID in addition to UID, PID validity, and the pinned 20-byte CDHash.
2. The root Helper derives the allowed peer GID from the installer-provisioned `socketGroupID`; a missing GID is rejected by manifest validation and by the deployment policy.
3. The App-side transport pins the Helper's peer GID to `0` as well as UID `0` and the provisioned Helper CDHash set.
4. The Darwin `csops(CS_OPS_CDHASH)` provider rejects an all-zero digest instead of treating a correctly sized but empty output buffer as an identity.
5. Unit coverage checks that an otherwise correctly pinned UID/CDHash is rejected when the kernel-reported GID differs from the provisioned GID.

## Authentication invariants

- UID/GID/PID are read from the connected socket's kernel peer credential APIs (`getpeereid` and `LOCAL_PEERPID` on Darwin).
- CDHash is obtained from `csops(pid, CS_OPS_CDHASH, ...)`; no CDHash is accepted from an IPC payload.
- The returned identity carries the same UID/GID/PID values that came from the socket credential query.
- A non-positive PID, failed `csops`, malformed CDHash, all-zero CDHash, UID/GID mismatch, or unpinned CDHash is a hard failure.
- The App verifies the Helper peer independently; the Helper verifies the App against its root-owned manifest.
- Nonce handshake is freshness/replay binding, not a replacement for kernel identity verification.

## Device validation procedure (NOT RUN here)

On the target RootHide device, after installing a signed build and a newly provisioned schema-2 manifest:

1. Record `id -u` and `id -g` for the installed App process using a trusted process inspection method; do not assume UID/GID 501.
2. Confirm the installed Helper socket owner is `root:<measured App GID>` and mode `0660`; confirm parent directories are searchable but not listable/writable by the App.
3. Run a Health request from the signed FilterKit App and preserve Helper audit output showing peer UID/GID/PID and the matched pinned CDHash identifier (never log secrets).
4. Run a negative test from a separately signed test client with a different CDHash. It must be rejected before request dispatch.
5. Run a same-UID/GID but different-CDHash negative test. It must also be rejected.
6. Confirm the App rejects a Helper with a non-root UID/GID or a CDHash not in AppTrust.
7. Repeat after Helper restart and after App restart to ensure there is no stale PID/session trust.

Do not log raw sensitive process metadata beyond what is needed for the signed test report. Never use a production App signing identity for the negative client.

## Validation performed in this environment

- Swift parser over all `Sources` and `Tests`: PASS.
- Project YAML parse and source-path validation: recorded by the P2-13 audit script.
- Focused policy smoke: checks matching UID/GID/CDHash accepted and wrong GID rejected.
- Darwin/iOS SDK compilation: NOT RUN (no Xcode/iOS SDK in this environment).
- Darwin `getpeereid`, `LOCAL_PEERPID`, and `csops`: NOT RUN on Darwin.
- RootHide launchd/socket/Health IPC: NOT RUN on device.
- XCTest suite: NOT RUN.

## Release gates

`HelperRequestDispatcher.pluginAssociationCommitReleased`, `HelperDeploymentCoordinator.pluginAssociationCommitReleased`, and all general execution gates remain `false`. P2-13 does not authorize enabling them.
