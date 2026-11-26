# P2-16 Changelog

- Added socket-aware peer identity provider protocol entry point while preserving existing test providers.
- Implemented Darwin `LOCAL_PEERTOKEN` acquisition in `DarwinPeerIdentityProvider`.
- Validated audit-token euid, egid, PID against `getpeereid` / `LOCAL_PEERPID` credentials.
- Re-read the token after `csops(CS_OPS_CDHASH)` and reject byte-level changes.
- Added `auditTokenDigest` to local peer identity evidence; raw audit-token bytes are not exposed.
- Required valid audit-token digest evidence on Darwin client and server transport paths.
- Added unit coverage for missing, malformed, and valid audit-token digest evidence.
- Kept `pidVersion` nil; no unverified PID-generation claim was introduced.
- Kept all production execution and plugin-commit release gates closed.
