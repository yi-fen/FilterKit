# P2-21 Validation Report

Date: 2026-11-26

## Executed on the available Linux host

- P2-16 compatibility audit: 11/11 passed.
- P2-17 static audit: 11/11 passed.
- P2-18 static audit: 10/10 passed.
- P2-19 static audit: 12/12 passed.
- P2-20 static audit: 12/12 passed.
- P2-21 static audit: 14/14 passed.
- Swift frontend parse across Sources, HelperRuntime, and Tests: see command output recorded at packaging time; all files passed.
- Focused Helper IPC/transport Swift typecheck: passed on Linux conditional compilation path.
- AF_UNIX Health Smoke: passed; nonce-bound round-trip and untrusted CDHash rejection.
- Audit sink Smoke: passed; bounded rotation, mode 0600, newline-complete append and fsync path.

## Not executed

- XCTest suite (including newly added XCTest methods).
- macOS/Xcode/iOS SDK build and Darwin-only compilation.
- RootHide device tests, real Darwin credential APIs, process-reuse stress, and production Helper lifecycle tests.

## Interpretation

The replay/freshness policy and its server integration pass source audits and focused host typechecking. Existing host smoke tests still pass. This does not establish durable exactly-once semantics: the replay cache is process-local, bounded (4096 entries), and retained for 600 seconds by default. Restart or capacity eviction can remove old IDs. Mutating operations must continue to rely on their transaction/idempotency controls. All production write gates remain disabled.
