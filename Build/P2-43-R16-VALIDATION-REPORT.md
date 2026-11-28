# P2-43-R16 Validation Report

## Baseline

- Input archive: `FilterKit-P2-43-R15-Source.zip`
- Expected SHA-256: `8686b004b343c9895b8e5699d54ba389b6b4fbef85268c3486139839c569c962`
- Baseline SHA-256 verified before extraction.
- `unzip -t` passed before extraction.
- Worktree: `FilterKit-P2-43-R16-Work/FilterKit-P2-42`; R15 archive and prior worktree were not modified.

## R16-specific validation

- Recovery Dry-run Host Smoke: 21/21 assertions passed.
- Recovery Dry-run Static Audit: 14/14 assertions passed.
- Crash-after-step rehearsal covers all seven modeled transaction steps.
- Adverse cases cover invalid Journal chain, pointer mismatch, and service-running state.
- Repeated assessment of an unchanged snapshot is deterministic.

## Scope and limitations

The R16 harness is a pure in-memory simulation. It is not an end-to-end test of the real Durable Journal Store, descriptor-relative filesystem observer, authenticated XPC observer, shared Darwin lock, launchd, or privileged transaction executor. No real filesystem mutation or service operation is performed. The rehearsal digest is non-cryptographic and cannot authorize any action.

Environment: Linux Swift 6.2.1. `xcodebuild` and Apple SDK are unavailable. Therefore no complete iOS/Helper target build, XCTest run, Darwin runtime validation, RootHide/ElleKit device test, or actual power-loss/kernel-crash injection is claimed. Production installation, activation, recovery, and rollback gates remain closed.
