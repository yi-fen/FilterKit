# P2-44-R17 — Recovery Fault Matrix

## Scope

R17 adds a Host-side recovery fault matrix around the production `HelperTrustedInstallerCoordinator.prepare()`, real Durable Journal / Previous Release / Staged Release stores, production `activate(... prepared:)`, and production `recover(durableJournal:...)` APIs.

## Production hardening

The partial-activation rollback path previously validated and restored artifacts one at a time. That ordering could unlink a newly activated file before discovering that its trusted Previous backup was missing. R17 changes recovery to:

1. Inspect the complete three-artifact Active set and all corresponding Previous backups before mutating any Active destination.
2. Accept only known Active states (missing, expected new hash, or expected old hash) and known backup states (missing or expected old hash).
3. Require a verified Previous backup whenever the old Active bytes are not already present.
4. Persist the activation record as `manualIntervention` and advance the Durable Journal to `manualIntervention` when evidence is unknown or insufficient.
5. Begin the rollback mutation phase only after the complete preflight succeeds.

This prevents a missing backup from causing an Active file to be unlinked before recovery discovers that restoration is impossible.

## Runtime coverage

The R17 Host smoke executes:

- Crash after executable replacement.
- Crash after deployment-manifest replacement.
- Crash after launch-daemon replacement.
- Rollback to the exact previous three-file byte set.
- Durable Journal transition to `manualIntervention` after a partial rollback.
- Idempotent second recovery after a completed rollback.
- Unknown Active bytes: recovery is blocked, unknown bytes remain untouched, and the Durable Journal enters `manualIntervention`.
- Repeated recovery remains blocked while the activation record is quarantined.
- No service-start operation is present in the activation/recovery executor.

The R16 regression scenario continues to cover a committed Active set with Pointer publication interrupted before the Pointer rename, followed by recovery publication and idempotency.

## Validation

- R17 recovery fault-matrix Host smoke: 54/54 assertions passed.
- R17 static recovery audit: 29/29 checks passed.
- R16 full Upgrade Host smoke regression: 28/28 assertions passed.
- R16 static full Upgrade audit regression: 33/33 checks passed.
- R15 Store write Host smoke regression: 16/16 assertions passed.
- R15 static Store write audit regression: 26/26 checks passed.

## Explicit exclusions

R17 does not claim runtime coverage for every `FaultPoint`. In particular, the pre-progress `.afterFirstActivation` / `.afterFirstProgressJournal` boundaries, `.afterCommittedJournal`, and `.afterPointerCommit` were not included in the final passing R17 matrix. R16's passing coverage remains specifically `.beforePointerRename`. A missing-backup runtime case was not retained in the final smoke; the all-artifact preflight ordering and no-unlink-before-preflight behavior are covered by static audit. These boundaries remain open for a subsequent Darwin/Host acceptance phase.

Host adapters still stand in for production Ed25519/code-signature verification, Mach-O metadata extraction, OS-derived peer credentials, live stopped-service observation, descriptor observer, and shared acceptance lock. This is not an Apple SDK/Xcode build, XCTest run, Darwin filesystem qualification, launchd/XPC test, or RootHide/ElleKit device acceptance.

## Production gates

No production write gate was opened. No Helper deployment, launchd bootstrap, service start/restart, or jailbreak filesystem mutation was performed.
