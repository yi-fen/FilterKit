# P2-37 Acceptance Checklist

- [x] Hard-bound and soft-associated plugin rows resolve against current App bundle ID.
- [x] Each App gets an independent observed state.
- [x] Hard-bound relationship is immutable while activation preview is allowed by the state policy.
- [x] Soft association manifest `isEnabled` cross-checks Filter.Bundles membership.
- [x] Third-party and unknown plugins are non-actionable.
- [x] Global / ambiguous / inconsistent / unavailable configuration locks the switch.
- [x] Local switch preview does not write or call Helper.
- [x] Release gates remain closed.
- [ ] macOS XcodeGen project generation and iOS SDK build.
- [ ] XCTest execution on iOS Simulator.
- [ ] Trusted manifest ownership verification in the deployed inventory pipeline.
- [ ] RootHide / ElleKit device validation (not part of P2-37 preview scope).
