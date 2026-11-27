# P2-37-R1 Acceptance Checklist

- [x] Refresh generation prevents stale scan results from replacing newer results.
- [x] Scan start increments a published snapshot revision.
- [x] Preview state is isolated by plugin ID and target bundle ID.
- [x] Preview state clears on a new scan revision.
- [x] Hard-bound binding is not modified by preview state.
- [x] Soft manifest state and Filter.Bundles are cross-checked.
- [x] Identity conflicts are rejected.
- [x] Missing/unverified identity evidence remains locked.
- [x] Third-party and unknown ownership remain locked.
- [x] English and Simplified Chinese strings added.
- [x] Host app-state audit (15/15) and activation smoke (8/8) pass.
- [x] P2-36-R1 / R2 Phase 2 / Phase 3 / Phase 4 static regression audits pass.
- [ ] Xcode/iOS SDK build and XCTest on macOS.
- [ ] RootHide device Helper identity attestation.
- [ ] Device IPC and crash/recovery validation.
- [ ] Any production mutation release review (out of scope for R1).
