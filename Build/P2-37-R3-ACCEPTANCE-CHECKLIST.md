# P2-37-R3 Acceptance Checklist

## Source-level / Host acceptance

- [x] Exact manifest bytes are hashed and decoded as one scan observation.
- [x] Dylib/plist/manifest metadata is checked before and after reads.
- [x] Helper attestation freshness is limited to 120 seconds.
- [x] Expired or changed-file attestations are invalidated and trigger a read-only rescan.
- [x] Temporary Helper unavailability is retried with a 30-second bound.
- [x] Helper payload hashes and Mach-O identity are compared with the local scan.
- [x] Complete soft-association set is compared with `Filter.Bundles`.
- [x] Disabled soft associations cannot appear in `Filter.Bundles`.
- [x] Undeclared App targets, global filters, and alternate match dimensions remain locked.
- [x] Hard-bound relationship remains permanent while its activation state can be off.
- [x] Multiple Apps have independent preview state.
- [x] Package-manager-owned and unverified third-party plugins remain read-only.
- [x] Unknown scanner ownership requires Helper-authored root-side proof.
- [x] App detail has no Helper mutation call and remains preview-only.
- [x] App and Helper production Release Gates remain closed.

## Apple / device acceptance — pending

- [ ] XcodeGen generation succeeds on macOS.
- [ ] FilterKit app target builds with the supported iOS SDK.
- [ ] FilterKitHelper target builds with the supported iOS SDK.
- [ ] XCTest suite passes in Apple XCTest Runner.
- [ ] Darwin peer identity and code-signature checks pass on device.
- [ ] Helper returns the expected fresh attestation for a known FilterKit plugin.
- [ ] Third-party/package-manager plugin is rejected on device.
- [ ] File replacement invalidates evidence and forces a new attestation.
- [ ] Helper restart / unavailable / recovery-pending states lock App controls.
- [ ] RootHide + ElleKit device verification is completed.

## Release decision

**Not approved for production mutation.** Keep all App and Helper mutation Release Gates closed until Apple-platform and device acceptance items above are evidenced.
