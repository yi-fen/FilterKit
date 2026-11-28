# P2-43-R10 Changelog

## Scope

R10 adds a journal-driven transaction orchestration layer for the future privileged Helper installer. It does not implement privileged filesystem operations and does not enable any production write gate.

## Changes

- Added `HelperInstallerJournalPersisting`, with the existing root-owned durable journal store conforming to the protocol.
- Added `HelperInstallerTransactionOperating` as a narrow operation boundary for artifact verification, previous-release preservation, staging, activation, service verification, rollback, and leaving the service stopped.
- Added `HelperInstallerTransactionExecutor`, which persists the journal at each completed phase and enforces the action order for install, upgrade, and repin.
- Added typed provisioning commit outcomes (`committed`, `rejected`, `indeterminate`) so a rejected commit can roll back while an indeterminate commit stops the service and records manual intervention.
- Added `HelperJournaledRootInstallerAdapter` to connect the journal executor to the coordinator contract. Its `isProductionReady` is permanently `false` in this phase.
- Updated the coordinator callback to use typed commit outcomes.
- Extended journal transitions so `serviceVerified` can enter rollback or manual intervention. This closes the prior inability to roll back after a provisioning commit rejection that occurs after service verification.
- Added XCTest source coverage for rollback after service verification, indeterminate commit journaling, and upgrade preservation ordering.
- Added a portable Host smoke harness and static audit.

## Safety boundaries

- No production Root Installer backend is supplied.
- No privileged file staging, replacement, launchd invocation, Keychain write, or Helper restart is implemented by this executor.
- Generated plans remain `executionEnabled == false`.
- The default root installer remains unavailable; the journaled adapter also reports `isProductionReady == false`.
- The existing boolean `operatorApproved` input remains insufficient for production authorization and is not upgraded into a trusted credential in R10.
