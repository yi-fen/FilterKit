# P2-37-R2 Acceptance Checklist

## Host/source acceptance

- [x] Request contains only request ID, plugin ID hint, safe leaf filenames, and timestamp.
- [x] Helper re-resolves package ownership.
- [x] Helper verifies root-owned schema-3 manifest and exact dylib/plist hashes.
- [x] Helper verifies Mach-O identity fingerprint.
- [x] Helper derives hard binding, soft association states, and Filter projection from verified files.
- [x] Dispatcher checks request binding, time window, clean recovery state, and audit availability.
- [x] Response is bounded to the IPC frame budget.
- [x] App binds response to request ID and short freshness window.
- [x] App compares Helper evidence with local scan evidence before preview eligibility.
- [x] Third-party, unknown, conflicting, stale, or mismatched identity remains locked.
- [x] All production mutation gates remain closed.

## Apple/device acceptance still required

- [ ] Generate Xcode project with XcodeGen on macOS.
- [ ] Build FilterKit app target with the supported iOS SDK.
- [ ] Build FilterKitHelper target with the supported iOS SDK.
- [ ] Run full XCTest suite.
- [ ] Verify signed App and Helper CDHashes on device.
- [ ] Verify Darwin peer credentials and Audit Token binding.
- [ ] Exercise the new identity-attestation IPC request on RootHide.
- [ ] Verify Helper audit records and clean-recovery gating.
- [ ] Verify package-owned and malformed plugin rejection on device.
- [ ] Confirm no mutation occurs during attestation.

P2-37-R2 is not device-accepted until every item in the second section has evidence.
