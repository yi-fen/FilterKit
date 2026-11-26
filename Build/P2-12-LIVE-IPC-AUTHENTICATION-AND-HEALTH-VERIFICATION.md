# P2-12 — IPC Authentication & Health Verification

## Scope

This stage hardens and verifies the AF_UNIX request path without enabling configuration writes. It is not a substitute for RootHide device validation.

## P2-11 integration defect found and fixed

The socket server's post-handshake allow-list previously admitted health, maintenance, operation, and deployment-batch requests, but omitted the already-implemented plugin-filter Prepare and Commit request types. Consequently, those requests could be rejected by the transport before reaching `HelperRequestDispatcher`.

P2-12 centralizes the server request allow-list in `HelperIPCServerRequestPolicy` and includes:

- `healthRequest`
- `maintenanceRecoveryRequest`
- `operationRequest`
- `deploymentBatchRequest`
- `pluginFilterMutationPrepareRequest`
- `pluginFilterMutationCommitRequest`

Handshake-only and response-only message types remain disallowed as client requests.

## Authentication path

1. App connects to the provisioned AF_UNIX socket.
2. Helper obtains peer UID/GID using `getpeereid` and PID using `LOCAL_PEERPID` on Darwin.
3. `DarwinPeerIdentityProvider` obtains the peer CDHash through `csops(CS_OPS_CDHASH)`.
4. Helper checks UID and CDHash against the installed deployment manifest.
5. Helper and App complete a fresh nonce-bound Hello/HelloAck exchange.
6. The server checks the request allow-list, nonce, timestamp, and request envelope before dispatch.
7. App independently obtains and verifies the Helper CDHash through its configured peer identity/trust providers.

Any unavailable credential, PID, CDHash, trust pin, nonce, or timestamp remains a hard failure. A successful socket connect alone is not authentication.

## Health verification

The Health request is read-only. A valid Health response must have the expected message type and request ID, carry the current protocol version, decode to `HelperStatusResponse`, report `helperReachable == true`, and contain a fresh timestamp. Recovery state is reported without attempting automatic repair.

## Validation added

- Unit coverage for allowed client request types.
- Unit coverage rejecting handshake-only and response-only types as client requests.
- Static audit ensures the live socket server uses the centralized policy and that Prepare/Commit are not omitted.
- Swift parser/typecheck checks are recorded in the P2-12 changelog.

## Device validation still required

The following cannot be proven by source inspection or host tests and remain NOT RUN:

- RootHide device UID/GID and socket-group provisioning.
- iOS `getpeereid` + `LOCAL_PEERPID` behavior on the target OS.
- `csops(CS_OPS_CDHASH)` access and returned CDHash on the target jailbreak.
- Real App-to-Helper bidirectional trust handshake.
- Real Health request/response over the installed launchd Helper.
- Negative connection tests from an untrusted signed process.

## Release gates

All deployment and plugin-association execution gates remain `false`. P2-12 does not install or launch the Helper, alter socket permissions on-device, write plugin configuration, or modify dylibs.

## Host AF_UNIX integration smoke (executed)

A temporary Linux host harness exercised the actual Swift `UnixDomainSocketServer` and `UnixDomainSocketTransport` over a real local AF_UNIX socket:

- Kernel peer credentials were obtained through Linux `SO_PEERCRED`.
- A deterministic test identity adapter supplied a test CDHash so the production trust-policy and nonce handshake path could be exercised without pretending Linux provides iOS `csops`.
- A Health request completed a nonce-bound Hello/HelloAck + request/response round-trip; the request ID and decoded clean status matched.
- A client-side trust pin mismatch was rejected before a request was dispatched.

This is host transport evidence only. It does not establish Darwin `getpeereid`, `LOCAL_PEERPID`, `csops`, iOS sandbox path access, or RootHide launchd behavior.
