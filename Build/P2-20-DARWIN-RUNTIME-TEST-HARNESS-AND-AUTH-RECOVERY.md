# P2-20 — Darwin Runtime Test Harness & Authentication Failure Recovery

## Scope

P2-20 adds a per-socket authentication lifecycle state machine and connects it to the Helper server's existing authentication path. It is designed to make ordering, failure, and cleanup behavior testable without claiming that a host test emulates Darwin kernel identity APIs.

## Runtime lifecycle

Each accepted socket receives an independent `HelperPeerAuthenticationLifecycle`:

`created → credentialsVerified → codeIdentityVerified → trustVerified → handshakeVerified → authenticated`

Out-of-order transitions are rejected. Any caught authentication failure marks the lifecycle failed. The `defer` cleanup closes it; close is idempotent and terminal. The lifecycle lock protects each instance's state. No peer identity or authentication state is shared between connections.

## Tests added

- Ordered stage progression and rejection of skipped stages.
- Failure followed by repeated failure/close cleanup; closed state cannot be resurrected.
- 256 concurrent independent lifecycle instances, alternating successful and rejected paths.
- Existing Audit Token/PID Generation evidence and diagnostic redaction tests remain in place.

## Validation boundaries

The static gate checks that the lifecycle is integrated into the actual server path and that all production write gates remain false. Host-side Swift parsing/typechecking and deterministic tests can validate the state machine. They cannot validate `LOCAL_PEERTOKEN`, `proc_pidinfo`, `pbi_pidversion`, Darwin permissions, real PID reuse, or RootHide behavior. Those still require macOS/Xcode and a target device.

## Safety

No plugin association commit, deployment execution, or production backend execution gate is enabled.
