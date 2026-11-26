# P2-19 — Darwin Authentication Integration & Runtime Diagnostics

## Goal

Make the existing P2-16/P2-17 peer-identity checks diagnosable without weakening their fail-closed behavior. This phase improves the Helper server's bounded authentication diagnostics; it does not claim Darwin runtime validation.

## Changes

- Added `HelperPeerIdentityDiagnosticError`, allowing a platform identity provider to return a stable, bounded diagnostic category without exposing its platform-specific error type through the transport API.
- `DarwinPeerIdentityProvider.IdentityError` now maps CDHash, Audit Token, and PID Generation failures to distinct reason codes (for example `peer_audit_token_changed` and `peer_pid_generation_read_failed`).
- The Helper server preserves those bounded reason codes instead of collapsing all provider failures into `peer_identity_provider_failed`.
- `HelperPeerAuthenticationDiagnostic` now records optional PID Generation and audit session ID plus booleans indicating whether Audit Token and complete process-generation evidence were present.
- The raw Audit Token digest is deliberately not included in diagnostics. The existing truncated CDHash behavior remains unchanged.
- Added unit-test coverage for complete/incomplete evidence diagnostics and a check that the serialized diagnostic does not contain the Audit Token digest.
- Added `Build/scripts/p219_static_gate_audit.py`.

## Verification on this host

- P2-19 static audit: 12/12 PASS.
- P2-18 static audit: 10/10 PASS.
- P2-17 static audit: 11/11 PASS.
- Swift frontend parse across `Sources`, `HelperRuntime`, `Tests`, and `Build/DarwinSDK`: PASS.
- Focused Linux typecheck for Helper models, diagnostics, transport, coordinator, and SHA-256 support: PASS.
- AF_UNIX nonce-bound Health smoke: PASS; untrusted CDHash rejected before request dispatch.
- Audit sink smoke: PASS; newline-complete append, mode 0600, bounded rotation, and fsync path exercised.
- `Project.yml` YAML parse: PASS.

## Not run / limitations

- XCTest suite was not executed.
- No macOS/Xcode/iOS SDK was available; the Darwin-only provider branch and SDK probe were not compiled against an Apple SDK in this phase.
- No RootHide device runtime, process-exit/PID-reuse kernel stress, or real `proc_pidinfo` authorization test was run.
- Host AF_UNIX tests do not validate Darwin `LOCAL_PEERTOKEN`, `LOCAL_PEERPID`, `proc_pidinfo`, or RootHide privilege behavior.

## Safety

All production execution and plugin-association release flags remain `false`. No production write path was enabled. Darwin authentication continues to reject missing Audit Token or PID Generation evidence.
