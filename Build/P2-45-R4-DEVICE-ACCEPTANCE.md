# P2-45-R4 — RootHide Device End-to-End Acceptance

## Status

**DEVICE_ACCEPTANCE_PENDING / HOST_QUALIFICATION_ONLY**

This phase cannot be marked device-passed from a Linux development host. No RootHide device, Apple SDK, launchd runtime, APFS volume, or device-side privileged Helper was available in this execution. The evidence collector and acceptance protocol are prepared; they do not fabricate device evidence.

## Entry conditions (hard blockers)

1. P2-45-R1: build App and Helper on macOS with the final deployment/signing model. Resolve `FilterKitHelper`'s current `CODE_SIGNING_ALLOWED: NO`; record signed artifact hashes, signing identifier, Team ID (if applicable), CDHash, entitlements, and provisioning/deployment format.
2. P2-45-R2: deploy the signed Helper on a disposable RootHide test device; capture kernel-derived peer credentials, audit-token stability, CDHash and signed identity, then pass a real App↔Helper IPC round-trip and rejection tests.
3. P2-45-R3: validate the actual device JBROOT, owner/group/mode contract, socket parent, artifact directories, no-follow behavior, Darwin exclusive rename, fsync and reboot persistence.
4. Preserve a recoverable device snapshot and have a tested manual recovery route before any mutation test.

## Evidence collection

Run `Build/scripts/p245_r4_device_evidence_collector.sh` from an explicitly authorized root shell on the test device. Set these values from the device's validated deployment manifest and inspection results; do not guess paths:

- `FILTERKIT_JBROOT` (required)
- `FILTERKIT_REPORT` (required; outside JBROOT)
- `FILTERKIT_HELPER_DIR` (optional)
- `FILTERKIT_ACTIVE_DIR` (optional)
- `FILTERKIT_SOCKET_PATH` (optional)
- `FILTERKIT_HELPER_BIN` (optional)
- `FILTERKIT_LAUNCHD_LABEL` (optional)

The collector is read-only with respect to JBROOT. It records device OS/build, boot-session UUID, UID/GID, supplied path metadata, optional launchd job visibility, and codesign diagnostics. It does not start/stop Helper, create a socket, alter permissions, rename files, or execute an activation transaction.

## Required manual device acceptance matrix

All mutation tests must use a disposable test release and a dedicated test JBROOT subtree explicitly approved for the device. Never point the test at live system files or user plugins.

| ID | Test | Required evidence | Pass condition |
|---|---|---|---|
| D1 | Device/build identity | OS version/build, device model, jailbreak version, boot UUID | Reproducible device identity recorded |
| D2 | JBROOT contract | Canonical path, owner/group/mode, symlink status | Matches the signed deployment policy; no inferred path |
| D3 | Helper artifact | SHA-256, codesign identifier, Team ID/CDHash, entitlements | Matches the approved build and provisioning pin |
| D4 | launchd lifecycle | Job label, launchd state, process PID/UID/GID | Only the intended signed Helper is launched |
| D5 | IPC positive path | Server/client logs, peer credentials, audit token, CDHash, Bundle ID, Team ID, nonce/session IDs | Authenticated round-trip succeeds |
| D6 | IPC negative path | Wrong identity/UID, stale nonce, replay, malformed frame logs | Every unauthorized request is rejected |
| D7 | filesystem boundary | JBROOT, Helper, socket-parent, Active/Previous/Staged metadata | Ownership, modes, type and no-follow checks pass |
| D8 | atomic replacement | Before/after hashes and rename return codes | Darwin exclusive no-replace semantics verified on APFS |
| D9 | three-file transaction | Three old/new hashes, Journal transitions, transaction ID | All three files commit as one recoverable release set |
| D10 | interrupted activation | Fault point, Journal bytes/state, Active/Previous hashes | Recovery restores a fully verified old set or stops for manual intervention |
| D11 | reboot recovery | Pre-reboot evidence, post-reboot evidence, launchd state | Recovery is idempotent; uncertain state never starts Helper |
| D12 | rollback/restart | Journal, Pointer, all three Active hashes, service state | Verified rollback and service restart only after validation |

Each row requires raw logs and SHA-256 evidence. A screenshot alone is insufficient for file identity or transaction state.

## Device mutation safety

- Do not enable any production execution gate during D1–D12.
- Use only disposable test artifacts with known hashes and a recovery image/snapshot.
- Stop on any unknown Active hash, missing/mismatched Previous artifact, Journal mismatch, identity mismatch, or ambiguous service state.
- Never auto-delete unknown files or attempt best-effort repair of an uncertain transaction.
- The Helper must remain stopped when recovery reports manual intervention.
- After every test, verify all Active bytes, Journal state, Active Pointer, and service state independently.

## Current host qualification

Host tests validate source behavior and Linux-host adapters only. They do not satisfy any device row above and cannot qualify APFS, Darwin `renameatx_np`, Apple code signing, launchd, RootHide privilege transitions, kernel audit tokens, or power-loss durability.

## Gate decision

**R4 NOT PASSED. R5 production write enablement is NOT AUTHORIZED.** Re-evaluate only after all D1–D12 rows have device evidence and R1/R2/R3 blockers are closed.
