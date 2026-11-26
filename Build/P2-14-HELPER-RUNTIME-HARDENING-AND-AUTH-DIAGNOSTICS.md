# P2-14 — Helper Runtime Hardening & Authentication Diagnostics

## Scope

P2-14 adds bounded authentication-stage diagnostics and a fail-closed socket-node self-check. It does not release plugin mutation or deployment execution.

## Authentication diagnostics

The AF_UNIX server emits separate events for:

1. kernel peer credentials observed (`UID`, `GID`, `PID`);
2. code identity read;
3. trust-policy acceptance or rejection;
4. existing handshake/request validation remains a separate protocol boundary.

Diagnostics use bounded reason codes. Only a 12-character CDHash prefix is attached to diagnostic events; the complete CDHash is not copied into this new diagnostic record. The runtime routes these events into the root-owned audit JSONL sink. Audit append failure does not convert a rejected peer into an accepted peer; the connection still fails closed.

## Socket startup self-check

After bind/chown/chmod and before listen, Helper uses `lstat` to verify the node is a socket, root-owned, has the provisioned group, and has the exact configured mode. It also opens the parent directory without following a symlink and requires root ownership, no group/world write bits, and at least one search bit. Any mismatch prevents listen.

The expected production profile remains `root:<provisioned-app-gid> 0660` for the socket and a root-owned, non-group/world-writable searchable parent (normally `0711`).

## PID lifecycle boundary

The kernel peer PID is captured from the connected socket and used for `csops(CS_OPS_CDHASH)`. This stage records missing PID and code-identity read failures distinctly. It does not claim pidversion/audit-token binding: those fields remain nil in the current Darwin provider. A future device-specific implementation may add stronger PID-generation evidence only after validating the target XNU API and OS range.

## Verification boundary

Host-side policy tests and source parsing can validate decision logic, not Darwin kernel behavior. The following remain NOT RUN until an actual RootHide device and Xcode/iOS SDK build are available:

- Darwin `getpeereid` and `LOCAL_PEERPID` behavior on the target OS;
- `csops(CS_OPS_CDHASH)` against a live App peer;
- launchd Helper socket ownership/mode after installation;
- root-owned audit file creation and rotation on-device;
- authenticated Health IPC using the real App and Helper signatures.

All production execution and plugin-association commit release gates remain false.
