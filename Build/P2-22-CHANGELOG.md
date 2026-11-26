# P2-22 — Helper IPC Recovery, Idempotency & Transaction Consistency

## Delivered
- Added a thread-safe deployment batch idempotency ledger binding `batchID`, immutable `batchSHA256`, and ordered operation request IDs.
- Matching retries are not re-executed: in-progress and indeterminate outcomes are reported distinctly; conflicting reuse of a batch ID is rejected.
- Deployment batch envelopes use the ledger instead of the generic envelope replay guard, while operation IDs remain protected against cross-batch reuse.
- Added unit coverage for digest/operation binding, indeterminate state, and dispatcher retry behavior.
- Added explicit documentation that this ledger is process-local only. After Helper restart, the durable transaction journal and filesystem observations remain authoritative; this phase does not claim durable exactly-once execution.

## Safety
- All production execution and plugin-association commit release gates remain `false`.
- No real filesystem mutation or production write path was enabled.
- Maintenance reconciliation remains unreleased.

## Validation limits
Host-side Swift parsing/typechecking and deterministic policy tests do not establish Darwin/iOS SDK compatibility or RootHide device behavior. Full XCTest, Xcode build, Darwin SDK compile, and device crash/restart testing require macOS/Xcode and a target jailbreak device.
