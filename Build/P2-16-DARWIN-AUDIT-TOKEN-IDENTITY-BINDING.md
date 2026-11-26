# P2-16 — Darwin Audit Token Identity Binding

## Scope

P2-16 adds socket-scoped Darwin peer identity evidence to the existing AF_UNIX authentication path. It does not release plugin configuration writes and does not claim a verified iOS device build.

## Implementation

- `DarwinPeerIdentityProvider` reads `LOCAL_PEERTOKEN` (`SOL_LOCAL`, option `0x003`) from the connected socket.
- The returned audit-token snapshot is checked against the socket's `getpeereid` UID/GID and `LOCAL_PEERPID` PID using the XNU audit-token euid/egid/pid fields.
- The same socket audit token is read again after `csops(CS_OPS_CDHASH)`. Any byte-level change rejects the peer identity.
- The exact token snapshot is represented in `HelperPeerIdentity` only by a SHA-256 digest; the raw token is not serialized or logged.
- Both client and server transports require a 64-character audit-token digest on Darwin before proceeding to trust evaluation and nonce handshake.
- Non-Darwin test providers retain the legacy protocol entry point through a default socket-aware protocol implementation.

## Important PID-version boundary

This stage deliberately does **not** populate `pidVersion`. `LOCAL_PEERTOKEN` is treated as opaque except for the documented audit-token euid/egid/pid/asid fields. No undocumented token word is mislabeled as a PID generation. A dedicated PID-version API or a validated audit-token-to-process-generation contract still requires target-SDK verification. The repeated same-socket token snapshot narrows the PID-reuse race during CDHash lookup but is not represented as a complete PID-version guarantee.

## Failure behavior

- Unsupported or unavailable `LOCAL_PEERTOKEN` fails closed on Darwin.
- Wrong token length, UID/GID/PID mismatch, token change during `csops`, invalid CDHash, or absent token digest rejects the connection.
- No fallback to PID-only authentication is permitted on Darwin.

## Verification performed in this workspace

- Swift frontend syntax parse across Sources, HelperRuntime, and Tests.
- Static audit of token acquisition, snapshot revalidation, Darwin evidence gate, and closed execution switches.
- Project YAML parse and source-path validation.
- ZIP integrity check.

## Not performed

- Xcode/iOS SDK build or XCTest run.
- RootHide device execution of `getsockopt(SOL_LOCAL, LOCAL_PEERTOKEN)`.
- Device verification of the option constant/availability across supported iOS versions.
- Real `csops` + audit-token race test, PID reuse stress test, or signed App/Helper handshake.

These are mandatory before any production release decision.
