# P2-11 — RootHide IPC Permission Architecture

## Scope / truth boundary

P2-11 bumps the Helper deployment manifest and installer provisioning bundle to schema 2, and replaces the previous world-writable socket proposal with a group-scoped filesystem access layer. It does not install or start Helper, does not enable plugin mutations, and does not claim a successful device connection. The App's actual effective UID/GID and all JBROOT ancestor permissions must be measured on the target device; `501` remains a compatibility default in source fixtures only and is not an asserted device fact.

## Access layout

| Artifact | Owner | Mode | Reason |
|---|---|---:|---|
| `JBROOT/Library/FilterKit` parent | `root:wheel` | `0711` | Allows path traversal without directory listing |
| Helper private directory | `root:wheel` | `0711` | Search/traverse only; no directory listing for App clients |
| `manifest.json` | `root:wheel` | `0600` | App cannot read trust pins directly |
| audit file | `root:wheel` | `0600` | App cannot read or alter audit history |
| `helper.sock` | `root:<measured App primary GID>` | `0660` | Only root and members of the provisioned App group can connect via DAC |

The trusted installer must create the parent directory and set its owner/mode before Helper starts. Helper binds only a previously absent socket path, assigns the provisioned group with `chown`, then applies `0660`. Existing paths are never unlinked by the runtime. Failure to set owner or mode aborts startup.

The GID is an access-control convenience, not an identity proof. Other processes in that group may reach the socket, but Helper must still reject them unless both peer UID and kernel-reported CDHash match the root-owned manifest. `getpeereid` failure, peer-PID retrieval failure, `csops(CS_OPS_CDHASH)` failure, malformed hash, or trust mismatch is fail-closed. No protocol request is dispatched before authentication.

## Required device measurements

1. On the signed App process, record `getuid()` and `getgid()`; do not infer them from a username or hard-code 501.
2. Record the complete path-component search permissions from `/` through JBROOT, `Library`, `FilterKit`, and `Helper`. RootHide path redirection and sandbox behavior may differ from ordinary POSIX mode-bit checks.
3. Generate fresh provisioning with `--client-uid` equal to the measured App UID and `--socket-gid` equal to its measured primary GID. The root manifest must contain the same `socketGroupID`.
4. Install through the trusted root installer. Verify directory `root:wheel 0711`, manifest `root:wheel 0600`, socket `root:<App GID> 0660`.
5. From the actual signed App process, attempt health IPC. Record connect result, `getpeereid` UID/GID, peer PID, and `csops(CS_OPS_CDHASH)` result.
6. Attempt with a second signed test process sharing the same UID/GID but a different CDHash. It may connect at the filesystem layer but must be rejected before request dispatch. Also test wrong UID, wrong GID, wrong App CDHash, and unavailable PID/CDHash APIs.
7. Verify App-side Helper identity: peer UID must be root and Helper CDHash must match AppTrust. Verify Helper-side App identity independently.
8. Exercise bounded-connection behavior and malformed/slow clients; ensure unauthenticated clients cannot starve the service. Do not weaken socket permissions to solve a failed connect.

## Probe

Run as root:

```sh
sh Build/Device/p211-ipc-permission-probe.sh \
  '<device-verified-jbroot>' '<measured-app-uid>' '<measured-app-primary-gid>' '<app-cdhash>'
```

This read-only probe checks mode-bit search access and installed metadata. It does not model iOS sandbox ACLs, validate the live App process, or prove `getpeereid`/`csops`; the real App-process health IPC test remains mandatory.

## Release gates

All existing commit and deployment gates remain `false`. The server continues to reject operation requests while `executionEnabled=false`. No plugin plist, manifest, or dylib is changed by P2-11.

## Known limitations / review items

- A 0711 directory reveals that a known socket pathname exists only if the caller already knows the path; it does not grant directory listing or access to 0600 files.
- Every ancestor directory must grant search permission. The probe's mode-bit calculation is necessary but not sufficient under iOS sandbox/RootHide vnode rules.
- GID membership can be broader than the FilterKit App. Kernel CDHash authentication is therefore mandatory, not optional.
- `csops` and XNU `LOCAL_PEERPID` constants/API behavior require validation on each supported iOS build.
- Connection limits and timeouts reduce but do not eliminate local denial-of-service risk. Device testing must include slow and unauthenticated peers.
