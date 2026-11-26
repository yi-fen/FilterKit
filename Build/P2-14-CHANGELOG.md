# P2-14 Changelog

- Added bounded peer-authentication diagnostic events for credentials, code-identity, and trust-policy stages.
- Added UID/GID/PID observations and a 12-character CDHash prefix; the new diagnostic event does not retain the full CDHash.
- Routed Helper authentication diagnostics into the protected root-owned audit JSONL sink.
- Added post-bind socket-node verification using `lstat`: socket type, root owner, provisioned group, and exact mode.
- Added parent-directory verification using `O_NOFOLLOW`: root owner, no group/world write bits, and searchable mode.
- Added unit tests for socket parent/node policy and bounded diagnostic fields.
- Documented that PID-generation/audit-token binding and all Darwin/RootHide device checks remain unverified.
- Kept all production execution gates closed.
