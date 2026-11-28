# P2-45-R2 — Helper Identity & IPC Production Qualification

## Scope

Qualify the existing App ↔ privileged Helper AF_UNIX transport trust boundary, add regression coverage for peer identity rejection paths, and preserve all production write gates as closed.

## Changes

- Added explicit diagnostic mapping for `HelperPeerTrustPolicy.TrustError.codeSigningIdentityUnavailable`; the server now emits a stable, non-sensitive reason code instead of collapsing this failure into a generic trust rejection.
- Added six XCTest regression cases covering missing/partial signed identity, UID mismatch despite a matching CDHash, malformed CDHash, socket credential mismatch, and malformed audit-token/zero-PID evidence.
- Added a 30-check static audit of Darwin peer identity acquisition, audit-token stability, SecTask identity extraction, client/server credential binding, handshake, replay guard, socket-node permissions, manifest validation, and closed production gates.
- Added a repeatable R2 validation runner.

## Existing production trust chain verified by source inspection

1. The Helper reads the connected peer credentials from the kernel socket.
2. On Darwin, the identity provider reads `LOCAL_PEERTOKEN`, validates its audit-token credentials against socket credentials, obtains CDHash with `csops`, then re-reads and compares the token.
3. Bundle/signing identifier and Team ID are read from `SecTaskCreateWithAuditToken`, not from the IPC envelope.
4. Client and server independently verify the peer identity against provisioned UID/GID/CDHash pins; the Helper additionally requires the configured client Bundle ID and Team ID.
5. A fresh nonce handshake precedes an allow-listed, time-bounded request; request IDs are protected by a replay guard.
6. Socket node and parent directory ownership/mode are checked before serving.

## Qualification status

**HOST_SOURCE_QUALIFIED / DARWIN_RUNTIME_PENDING**.

This environment is Linux and has no Xcode, iOS SDK, Apple `codesign`, launchd, or RootHide device. The Darwin-only code was parsed as source but not compiled against an Apple SDK or executed against kernel audit tokens. XCTest was not executed. No actual Helper code signature, CDHash, launchd job, or XPC/AF_UNIX production installation was produced or accepted in this phase.

The Helper target still has `CODE_SIGNING_ALLOWED: NO` from R1. This remains an explicit production blocker. No production write gate was opened.

## Executed validation

- R2 static audit: 30/30.
- Swift parse: 275/275.
- R1 write-gate audit: 10/10.
- R18 Host recovery regression: 80/80.
- R17 Host recovery regression: 54/54.
- 30 shell scripts passed `bash -n`; Project.yml parsed; both 519-key localization files passed parity and `plutil -lint`.
