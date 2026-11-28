# P2-43-R11 Changelog

## Scope

Add write-ahead operation intents and conservative crash reconciliation to the R10 Helper installer transaction framework. Production execution remains disabled.

## Changes

- Upgrade `HelperInstallerTransactionJournal` to schema version 2.
- Add durable pending-operation tracking and intent events for artifact verification, previous-release preservation, staging, activation, service verification, and Provisioning commit.
- Completion events are accepted only when the matching intent is pending; journal chain replay reconstructs and verifies the pending-operation state.
- Update `HelperInstallerTransactionExecutor` to persist each intent before invoking its operation and persist completion afterwards.
- If an operation may have completed but its completion record cannot be confirmed, preserve the intent, stop the service, and require filesystem reconciliation rather than blindly rolling back.
- Stop the service before attempting rollback.
- Add `HelperInstallerCrashRecoveryEngine`, a side-effect-free decision engine based on a descriptor-verified filesystem/service/Provisioning snapshot.
- Recovery distinguishes already-completed operations, idempotent retries, target-vs-previous Provisioning authority, unexpected artifact hashes, and manual-intervention cases.
- Upgrade/Repin recovery requires the expected previous-release hashes and ownership evidence before continuing past the verification phase.
- Update journal-only recovery assessment to expose pending operations and the next operation after a durable completion.
- Update existing installer journal tests and add crash-recovery XCTest coverage.

## Compatibility

R10 journal schema version 1 is intentionally rejected by the R11 validator. It is not silently reinterpreted because R10 journals do not contain write-ahead intent records. An interrupted v1 transaction must remain stopped and be reconciled from actual filesystem and Provisioning state by a separately reviewed migration/recovery procedure.

## Security boundary

No production Root Installer backend, filesystem observer, launchd controller, or automatic recovery executor is added. `HelperJournaledRootInstallerAdapter.isProductionReady` remains `false`; generated execution plans remain disabled. The recovery engine returns decisions only and performs no writes.
