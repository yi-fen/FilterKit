# P1-35 — Trusted Root Installer Transaction Framework

## Scope

P1-35 advances P1-34's declarative installer plan with three pieces of implementation:

1. A release artifact verifier that checks the exact staged Helper executable and launchd plist bytes against the SHA-256 inventory, and validates the launchd plist's fixed identity and disabled lifecycle flags.
2. A pure transaction-journal state machine for install, upgrade and re-pin. It enforces event ordering, records sequence/state transitions, and computes a SHA-256 hash chain over each event.
3. An explicit execution gate. Because no production Root Installer adapter or authenticated release-provenance verifier exists, every current transaction plan remains `executionEnabled=false` and is rejected before any platform operation.

## Release artifact verification

`HelperInstallerReleaseVerifier` accepts only these two fixed relative paths:

- `usr/libexec/filterkit-helper`
- `Library/LaunchDaemons/cn.yfen.filterkit.helper.plist`

It rejects missing/extra artifacts, invalid digest inventories, byte-level SHA-256 mismatches, and launchd plists that do not have the exact FilterKit label/program path or that enable `Disabled`, `RunAtLoad`, or `KeepAlive`.

This is a byte-integrity check only. It does not parse Mach-O code signatures, derive kernel CDHashes, validate a CMS/notarization signature, or authenticate release provenance. The final App/Helper CDHashes remain post-signing inputs from a trusted signing pipeline, and a future Root Installer must independently verify installed code identity.

## Transaction journal

`HelperInstallerTransactionJournal` supports `install`, `upgrade`, and `repin` release transactions. It rejects unsupported action types and out-of-order events. Upgrade/re-pin must preserve the previous release before staging. Activation and service verification must precede commit. Failures can enter rollback-required, then rolled-back or manual-intervention states.

Every event records sequence, prior state, event, resulting state, previous hash and event hash. `validateChain()` replays the event hash calculation and checks sequence, state continuity and final head. This unkeyed hash chain detects accidental corruption or inconsistent edits; it is not an authentication mechanism and cannot prevent an attacker with write access from rewriting the entire journal.

The journal is currently an in-memory/Codable model. A durable Root-owned store, atomic replacement, fsync ordering, crash recovery executor and anti-rollback storage are not implemented in this phase.

## Execution boundary

`HelperInstallerExecutionGate` checks the plan release flag, presence of a Root Installer adapter, provenance verification, signed-artifact verification and explicit operator approval. Current `HelperInstallerTransactionPlan.make(...)` always returns `executionEnabled=false`, so the gate rejects with `planNotReleased` even when all evidence flags are supplied.

There is no production filesystem/launchd adapter, no arbitrary command execution, and no App-to-root privilege escalation route. The new code does not install, replace, remove, chown, chmod, bootstrap or bootout any file/service.

## Explicitly not implemented

- Privileged Root Installer executable, jailbreak package integration or installer authorization entry point.
- Cryptographically signed provisioning/release envelope and trust-root management.
- Mach-O code-signature validation and actual installed Helper CDHash re-check.
- Durable root-owned transaction journal, fsync, atomic activation and crash recovery.
- Real previous-release preservation/restore, filesystem ownership/mode enforcement, launchd bootstrap/bootout.
- Socket directory creation/verification/removal.
- Settings production coordinator wiring.
- Xcode/iOS/Darwin build, XCTest execution, or RootHide/Rootless device validation.

No actual Helper installation, launchd operation, TweakInject write, target App modification or target App re-signing was performed.
