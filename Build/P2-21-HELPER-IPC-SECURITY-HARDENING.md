# P2-21 — Helper IPC Security Hardening & Connection Stress Testing

## Scope

P2-21 strengthens the server-side request boundary after peer authentication. It does not change the plugin deployment authorization model and does not release production writes.

## Request validation order

For each authenticated socket, the server now checks:

1. The message type is in `HelperIPCServerRequestPolicy.allowedRequestTypes`.
2. The envelope nonce matches the freshly authenticated session nonce.
3. The envelope timestamp is within the inclusive ±120-second freshness window.
4. The request UUID has not already been accepted by the process-local replay guard.
5. Only then is the application request handler invoked.

A duplicate UUID is rejected before dispatch and emits a bounded `requestValidation` diagnostic with reason `duplicate_request_id_rejected`.

## Replay guard limits

The server uses the existing lock-protected `HelperRequestReplayGuard` shared by accepted connections. Its default retention is 600 seconds and capacity is 4096 IDs. It is process-local and bounded: after capacity eviction or Helper restart, an old UUID may become admissible. The fresh session nonce remains mandatory, and request IDs should be freshly generated UUIDs. This is not a durable exactly-once transaction journal; mutating operations still require their own idempotency/transaction protections.

## Existing transport bounds retained

- Maximum concurrent accepted handlers remain bounded by `maximumConnections` (default 8); excess accepted sockets are immediately closed.
- Socket receive/send timeouts remain 5 seconds on the server.
- Frames remain length-prefixed and capped at `HelperIPCEnvelope.maximumFrameBytes` (96 KiB).
- `readExactly` loops across fragmented stream reads and treats EOF/zero-byte reads as failure.
- Each connection handles one request and is closed after its response; no cross-connection session state is shared.

## Tests added

- Inclusive freshness-window boundaries and stale/future rejection.
- 256 concurrent attempts to consume one request UUID; exactly one may succeed.
- Distinct UUID acceptance and duplicate rejection.
- Static gate verifies replay validation occurs before handler dispatch and production write gates remain false.

## Validation boundaries

Host tests exercise the replay policy and source-level transport integration. They do not emulate Darwin socket credentials, `LOCAL_PEERTOKEN`, `proc_pidinfo`, iOS scheduling, or RootHide runtime behavior. Full XCTest and Apple SDK builds require macOS/Xcode; device stress testing remains outstanding.

## Safety

All production plugin-association commit and deployment execution gates remain `false`.
