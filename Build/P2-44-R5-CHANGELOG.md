# P2-44-R5 — Active Three-File Transaction Qualification

## Changes

- Extended the existing `HelperRootAtomicActivationExecutor`; did not add a second Active installer or another scanner/cache.
- Added a Journal-bound activation entry point. It requires a persisted `staged` Journal with `activateRelease` intent and binds the internal activation record to the same Transaction ID.
- Requires a complete staged inventory whose three observed hashes equal the exact signed/release-verified bytes to be activated.
- Upgrade/repin additionally require a complete Previous Release inventory whose hashes equal the expected previous Active hashes. First install rejects an unexpected Previous inventory.
- Validates the authenticated service observer challenge, OS-derived peer identity and pinned observer identity; the service must be observed stopped.
- Re-reads the Durable Journal and validates the service observation after acquiring the existing persistent `.filterkit-root-activation.lock` inode. The existing descriptor-relative three-file replacement and per-file read-back hash checks remain the mutation core.
- Writes Durable Journal `activateRelease` completion only after all three Active artifacts and the internal committed record are durable, but before deleting transaction backups or clearing the internal record.
- If Durable Journal completion is indeterminate, preserves the committed internal record and backups. Recovery rechecks all Active hashes and can finish the Journal transition before cleanup.
- If a partial transaction is safely rolled back, recovery marks the Durable Journal for manual intervention rather than silently continuing.
- No launchd start/bootstrap, Helper service start, production backend wiring, or release-gate opening was added.

## Host validation

`Build/scripts/run_p244_r5_active_transaction_smoke.sh` compiles and executes the real `HelperRootAtomicActivationExecutor.swift` and SHA-256 implementation with narrow Host shims for app/OS contracts. It covers successful three-file activation, incomplete staged rejection, stale observer challenge rejection, running-service rejection, Journal completion uncertainty, committed-state reconciliation, and partial-activation rollback/manual-intervention handling.

This Host smoke does not prove Darwin launchd/XPC behavior or a complete production integration. The Staged/Previous inspection values are supplied by the caller; the executor independently verifies the signed release bytes and current Active preimage under the shared lock, but R5 does not yet provide a single locked reader API that loads bytes directly from the R3/R4 stores. Production wiring remains closed pending that integration and device acceptance.
