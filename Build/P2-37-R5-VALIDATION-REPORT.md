# P2-37-R5 Validation Report

## Baseline

- Input: `FilterKit-P2-37-R4-Activation-Protocol.zip`
- SHA-256: `af5ac4f36e4dd2e46fb130266e632d6306a452f6f54f887d6d5abab56ed84051`
- ZIP integrity: passed before extraction.

## Implemented

- Added dedicated APP activation prepare/commit IPC message types and request allowlist entries.
- Wired prepare and commit authorization routes into `HelperRequestDispatcher`.
- Reused authenticated-session checks, request freshness, process-local replay guard, recovery status, and audit sink.
- Helper independently reads actual target activation state from the freshly authorized manifest and checks `expectedEnabled` on both prepare and commit.
- Prepare returns a validated R4 plan only after durable audit acceptance.
- Commit reauthorizes from fresh files but remains fail-closed with `execution_disabled`; no transaction is executed.
- Added dispatcher tests for allowlist boundaries, malformed payloads, and replay rejection.

## Executed validation

| Check | Result |
|---|---:|
| P2-37-R5 IPC static audit | **21/21 passed** |
| P2-37-R4 protocol audit (updated for R5 wiring) | **15/15 passed** |
| P2-37-R3 activation consistency audit | **25/25 passed** |
| P2-37-R2 Helper identity audit | **29/29 passed** |
| P2-37-R1 App-state audit | **15/15 passed** |
| P2-36-R1 association audit | **12/12 passed** |
| P2-36-R2 Phase 2 transaction audit | **17/17 passed** |
| P2-36-R2 Phase 3 IPC audit | **18/18 passed** |
| P2-36-R2 Phase 4 Apple-gate audit | **13/13 passed** |
| Swift frontend parse of Sources, App and Tests | Passed |
| ZIP integrity after packaging | Passed (all archive entries tested) |

The Swift frontend parse validates syntax only; it is not a complete iOS semantic build. No Xcode/iOS SDK is available in this environment, and XCTest has not been run in Apple's test runner.

## Not executed / pending

- Apple Xcode/iOS SDK build and XCTest Runner.
- Live signed App-to-Helper IPC on Darwin.
- RootHide / ElleKit device tests, including concurrency, Helper restart and crash recovery.
- Production transaction execution and post-commit proof. Release gates remain closed.
