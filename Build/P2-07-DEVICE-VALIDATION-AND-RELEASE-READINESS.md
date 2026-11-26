# P2-07 — Device Validation & Commit Release Readiness

## Purpose and release decision

P2-07 establishes a reproducible pre-release audit and a device-validation protocol. It does **not** claim that RootHide device validation has occurred. The current workspace has no attached iOS jailbreak device, Xcode/iOS SDK build environment, device console, or signing/CDHash evidence. Consequently, the commit release gates remain closed.

## Audited code path

1. App coordinator requires explicit `userConfirmed` and checks its independent release gate before transport submission.
2. Helper dispatcher validates the authenticated session/envelope, freshness, replay ID, request shape, and clean recovery state.
3. Helper checks its independent commit release gate.
4. Helper re-runs `HelperPluginFilterMutationAuthorizer.prepare` against current on-disk state.
5. A durable pre-commit audit record is required before invoking the two-file transaction.
6. P2-05 transaction stages and verifies plist + manifest, backs up both, replaces them sequentially, verifies final hashes, and journals recovery.
7. A completion audit is best-effort after commit so an already-committed operation is not falsely reported as failed.
8. App validates response type, request/plugin/action/target identity, disposition, transaction ID rules, hashes, and receipt freshness.

## Release-gate inventory

| Gate | Current value | Required evidence before change |
|---|---:|---|
| `HelperRequestDispatcher.pluginAssociationCommitReleased` | `false` | Full device matrix below passes; signed Helper identity verified |
| `HelperDeploymentCoordinator.pluginAssociationCommitReleased` | `false` | App UI-to-coordinator integration and live IPC round-trip pass |
| `HelperRequestDispatcher.executionReleased` | `false` | Separate deployment release review; not part of P2-07 |
| `HelperDeploymentCoordinator.executionReleased` | `false` | Separate deployment release review; not part of P2-07 |
| `HelperProductionDeploymentBackend.executionReleased` | `false` | Separate deployment release review; not part of P2-07 |

No gate is changed by this phase.

## Device validation protocol (must be run on supported RootHide + ElleKit device)

### A. Build, signing, and peer identity

- Build App and Helper with the project's supported Xcode/iOS SDK toolchain.
- Record Xcode version, SDK, deployment target, device model, iOS build, RootHide version, ElleKit version, architecture, and jailbreak root.
- Verify Helper executable owner/mode, code signature, designated requirement, Team ID where applicable, CDHash, and the exact peer identity observed by the Unix-domain socket server.
- Confirm an untrusted process, wrong UID/GID/PID binding, stale session, stale envelope, and replayed request are rejected.

### B. Read-only baseline

- Capture plugin dylib, paired Filter.plist, `.fk.json`, owner/group/mode, inode, and SHA-256 before testing.
- Verify package-owned and evidence-missing plugins fail closed.
- Verify hard-bound association cannot be removed.
- Verify disabling is rejected when Classes/Executables match dimensions remain capable of matching.
- Verify an existing unexpected/global filter rule is not silently normalized.

### C. IPC and authorization

- Exercise health, prepare, and commit protocol using the actual signed App and Helper.
- Confirm the App cannot send commit without explicit confirmation.
- Confirm stale prepare hashes, modified manifest, replaced plist, changed ownership, changed package ownership, path traversal, malformed Bundle ID, and wrong plugin/file pairing are rejected.
- Confirm commit performs fresh authorization; do not rely on a prior prepare response.
- Confirm pre-commit audit failure prevents any filesystem change.

### D. Transaction fault injection

Use a disposable FilterKit-owned test plugin and a recoverable test filesystem state. Inject process termination at every journal phase: journal persisted, each temp staged, each backup created, plist replaced, manifest replaced, final verification, committed marker, and cleanup. After restart, verify either both old files or both new files are present, never accept a mixed state as committed. Unknown hashes and missing backup evidence must stop for manual intervention. Repeat recovery to establish idempotence.

### E. ElleKit behavior and rollback

- Enable for a disposable test App and verify injection occurs only in the intended target.
- Disable and verify injection stops after the relevant process restart/respring semantics are accounted for.
- Verify unrelated Apps remain unaffected.
- Verify hard-bound Apps remain injected where required by policy.
- Restore the captured original files and verify exact hashes/metadata.
- Reboot/respring and repeat to detect persistence or startup recovery issues.

### F. Evidence package

Attach raw build logs, signing/CDHash output, Helper logs, audit journal, before/after hashes, transaction journal snapshots, fault-injection outcomes, target-App injection observations, and rollback verification. Record any untested item as NOT RUN, never PASS.

## Automated checks available in this source package

Run from repository root:

```sh
python3 Build/scripts/p207_static_gate_audit.py
find Sources HelperRuntime Tests/UnitTests -name '*.swift' -print0 | xargs -0 swiftc -frontend -parse
```

The static audit is intentionally narrow and read-only. It is not a substitute for XCTest, an iOS build, signed Helper validation, or RootHide device testing.

## Explicitly not established by P2-07

- No Xcode/iOS SDK build.
- No XCTest execution.
- No live App↔Helper IPC round-trip.
- No signing, designated-requirement, or CDHash verification.
- No RootHide/ElleKit device validation.
- No actual plugin file mutation or injection observation.

## Release recommendation

**NO-GO for enabling either plugin-association commit gate.** Continue with gates closed until all device protocol sections A–F are completed and independently reviewed. P2-07 is a release-readiness package, not a production release authorization.
