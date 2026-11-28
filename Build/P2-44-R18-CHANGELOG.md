# P2-44-R18 — Recovery Boundary Completion

## Production source change

- `HelperRootAtomicActivationExecutor` now performs a complete read-after-rollback verification of every Active artifact before persisting the transaction phase as `rolledBack`.
- Each restored Active hash must equal its trusted Previous hash; artifacts that were absent before the upgrade must remain absent.
- A mismatch records `manualIntervention`, advances the Durable Journal to `manualIntervention` when available, and stops recovery rather than reporting a successful rollback.
- The existing complete rollback preflight remains before any Active mutation. Missing or unknown Previous evidence leaves the current Active presence/bytes untouched.

## Recovery smoke correction

- Corrected the missing-Previous-backup test fixture to snapshot both presence and bytes after an injected partial activation. During that state, artifacts not yet activated may legitimately be absent from Active because their trusted Previous copies reside in transaction backups.
- The earlier Launch Daemon / Deployment file-not-found symptom was a test-fixture expectation error, not evidence that recovery had deleted a restored artifact. The corrected test checks exact pre-recovery presence and bytes and passes.
- The isolated Host fixture is rebuilt between the missing-backup quarantine case and the independent unknown-Active-bytes case. This is test cleanup only; it does not alter production recovery behavior.

## Fault matrix covered

- Crash after each of the three Active artifact replacements.
- Fault after first progress Journal persistence.
- Fault after Committed Journal persistence.
- Fault before Active Pointer rename.
- Fault after Active Pointer commit.
- Missing Previous backup: no Active mutation, Durable Journal manual intervention, repeated recovery remains blocked.
- Unknown Active bytes: no overwrite, Durable Journal manual intervention, repeated recovery remains blocked.
- Rollback read-after-write verification and repeat-recovery idempotency.

## Production boundary

- No production write gate was opened.
- The executor remains standalone and is not wired to HelperRuntime or the production deployment backend.
