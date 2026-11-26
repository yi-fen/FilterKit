# P2-15 — Socket Peer Revalidation & Audit Durability

## Scope

P2-15 hardens the existing AF_UNIX peer binding and root-owned JSONL audit sink. It does **not** claim to implement a Darwin Audit Token or kernel PID-generation token.

## Socket peer binding

Both client and server now:

1. Read UID/GID/PID from the connected socket (`getpeereid` + `LOCAL_PEERPID` on Darwin; `SO_PEERCRED` on Linux).
2. Resolve the peer code identity using the platform identity provider.
3. Re-read credentials from the same connected socket.
4. Reject if the two credential snapshots differ, PID is invalid, or the identity provider returns UID/GID/PID values that differ from the socket credentials.
5. Only then evaluate the pinned trust policy and proceed to the nonce handshake.

This binds the CDHash lookup to a stable credential snapshot exposed by the same socket. It is a mitigation for inconsistent snapshots, not a substitute for an Audit Token / PID version. `HelperPeerIdentity.pidVersion` and `auditSessionID` remain `nil` in the Darwin provider until a target-SDK-verified implementation is available.

## Audit durability

`HelperAuditFileSink` now:

- Calls `fsync(fileFD)` after each complete JSONL append.
- Calls `fsync(directoryFD)` to persist file creation and directory-entry changes.
- Calls `fsync(directoryFD)` after rotation renames.
- Retains the existing `openat` + `O_NOFOLLOW`, root ownership, regular-file and exact `0600` checks.
- Fails the append operation if file or directory synchronization fails.

The dispatcher already treats an audit failure as a hard failure for Health and other audited operations; write-capable operations remain behind closed release gates. Rejection responses remain denials even if the rejection audit itself cannot be persisted; that condition is not converted into authorization.

## Tests and host probes

- `HelperPeerIdentityBindingTests.swift` covers stable credentials, changed PID, and UID/GID/PID identity binding.
- `Build/Host/run-p212-afunix-health-smoke.sh` exercises a real Linux AF_UNIX Health round-trip using a private root-owned test directory, including credential revalidation and rejection of an untrusted peer.
- `Build/Host/run-p215-audit-sink-smoke.sh` exercises JSONL append, mode `0600`, bounded rotation, and the fsync path in a private temporary directory.

## Explicitly not verified

- Darwin `LOCAL_PEERPID` semantics on the target iOS version.
- Darwin `csops(CS_OPS_CDHASH)` against a live RootHide process.
- Audit Token / PID version binding.
- iOS filesystem `fsync` behavior and RootHide ownership layout.
- Xcode/iOS SDK build, XCTest, launchd deployment, or RootHide device execution.

All production execution gates remain closed. No device files are changed by these host probes.
