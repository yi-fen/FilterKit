# P1-32 — Helper Status IPC & App Integration

## Scope

P1-32 exposes the existing Helper recovery state to the App through authenticated IPC and adds an App-facing status model/coordinator API. It does not release deployment or recovery mutation.

## Changes

### 1. Structured health response

`healthResponse` now carries `HelperStatusResponse`:

- `helperReachable`
- `recoveryStatus`
- `checkedAt`
- `protocolVersion`

`recoveryStatus` is path-free and uses stable values:

- `clean`
- `legacyRecoveryRequired`
- `threeFileRecoveryRequired`
- `bothRecoveryRequired`
- `invalidJournal`
- `unavailable`

The Helper derives the value from the read-only `HelperStartupRecoveryCheck.inspectDetailed` call. No filesystem path, peer identifier, hash, or audit contents are exposed to the App.

### 2. Restricted status-only service mode

A pending or invalid journal no longer needs to make the Helper socket completely unreachable. Runtime can keep the authenticated IPC endpoint online so the App can inspect the problem.

The Dispatcher checks the current recovery state before either legacy operation or deployment-batch execution:

- pending recovery -> `recovery_required`
- invalid/unavailable journal state -> `invalid_transaction_journal`
- only clean state can proceed to the already-closed execution release gate

Health and maintenance inspection remain available. The release gates remain false, so this is a status-only service while recovery is pending.

### 3. Authenticated maintenance request protocol

Added `maintenanceRecoveryRequest` / `maintenanceRecoveryResponse`.

The request is protected by the existing AF_UNIX peer trust, handshake nonce, authenticated peer context, request timestamp and replay guard. It includes an action, a non-zero request nonce and timestamp.

- `inspect` returns the current recovery status and is read-only.
- `reconcileThreeFileTransaction` is recognized but returns `recoveryNotReleased`.

No request from the App can currently trigger file recovery. This is an explicit release boundary, not an incomplete silent fallback.

### 4. App-facing coordinator and Settings UI

`HelperDeploymentCoordinator.fetchStatus()` decodes and validates the structured health payload. `healthCheck()` remains as a compatibility convenience.

`requestMaintenanceRecovery(_:)` submits an authenticated maintenance request and reports `recoveryNotReleased` if the caller asks to reconcile while the release gate remains closed.

Settings now has a Helper section showing connection state and recovery state, with a refresh action. The current app composition does not yet construct/inject a production `HelperDeploymentCoordinator`, because App-side peer trust material and the Darwin socket configuration have not been device-validated. The UI therefore truthfully displays “Not configured” until a coordinator is injected; it does not claim a live connection.

## Security invariants

- `HelperRequestDispatcher.executionReleased == false`.
- `HelperDeploymentCoordinator.executionReleased == false`.
- `HelperProductionDeploymentBackend.executionReleased == false`.
- Manifest template `executionEnabled == false`.
- No startup auto-recovery.
- No App-triggered recovery mutation.
- Plugin deletion remains unavailable.
- No target App Bundle modification or re-signing.

## Validation

The Linux smoke test verifies structured health status for a clean directory, invalid journal visibility, authenticated maintenance inspection, recovery request fail-closed behavior, replay rejection, audit entries, deployment rejection while the journal is invalid, and no filesystem mutation by maintenance requests.

The full Swift source parse and Helper/Runtime Linux typecheck pass. Project configuration, architecture and localization parity checks pass.

Not run: XcodeGen, Xcode/iOS SDK build, XCTest, Darwin compile, code-signing/CDHash validation, launchd installation, RootHide/Rootless device validation, real TweakInject writes, or device power-loss tests.
