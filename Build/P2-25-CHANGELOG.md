# P2-25 Changelog — Authorized Transaction Recovery & Ledger Finalization

- Added a transaction-scoped recovery capability requiring explicit operator confirmation, root socket credentials, peer/identity credential equality, a fresh authenticated session, Audit Token digest evidence, and PID Generation evidence.
- Recovery capability expires after the bounded authorization window and is bound to one exact Transaction ID and request nonce.
- Replaced the unscoped recovery-coordinator entry point with an authorization-bearing API that requires the durable Batch Ledger.
- Recovery now compares Batch ID, Batch digest, Transaction ID, Request IDs, plugin identity, artifact hashes, auxiliary files, and journal phase before mutation.
- Added transaction-ID-bound executor reconciliation.
- Added a two-step recovery completion protocol: reconcile files while retaining the transaction journal; durably finalize the Batch Ledger; re-check destination/backup/temp hashes; then clear the journal.
- This retained-journal ordering makes a crash between filesystem reconciliation and ledger finalization retryable without losing the recovery marker.
- Added terminal `rolledBack` ledger state so a rolled-back Batch ID cannot be submitted again as a fresh deployment.
- A committed transaction finalizes as `completed`; a pre-commit transaction finalizes as `rolledBack`.
- Added accepted-before-mutation and best-effort completion audit events. If the initial audit append fails, recovery does not mutate files.
- Startup inspection remains read-only. Ordinary IPC does not invoke the recovery coordinator.
- All deployment and plugin-association production release gates remain disabled.
