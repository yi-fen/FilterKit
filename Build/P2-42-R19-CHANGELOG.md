# P2-42-R19 — APP Activation Commit Outcome Reconciliation

Baseline: `FilterKit-P2-42-R18-Source.zip` (SHA-256 `45c303b1b209840272eac420c558f52c7a3d84cb20273749dd191c7357556fe3`).

## Scope

R19 addresses the APP activation UI's lost/invalid Commit response path. A transport error after Commit submission is not evidence that the operation failed, and the App must not automatically resubmit the same mutation.

## Changes

- Added `AppPluginActivationOutcomeReconciler`, which compares a fresh, cross-checked APP activation observation with the original command's expected and desired state.
- Reconciliation distinguishes `desiredStateObserved`, `previousStateObserved`, and `stillIndeterminate`.
- A matching observation requires the exact Plugin UUID, canonical Bundle ID, a matched manifest/Filter.plist cross-check, and a determinate enabled bit.
- `AppPluginActivationOperationStore` retains the uncertain command after a transport failure or invalid Helper proof, then accepts reconciliation only for the matching Plugin/App row.
- APP rows retry reconciliation when a newer shared PluginScanRegistry snapshot is published. This consumes the existing snapshot; it does not start a new scanner or add polling.
- While outcome remains unknown, the APP toggle is blocked and the store refuses another Prepare. No automatic Commit retry is performed.
- Even when the desired state is observed, the phase remains `outcomeUnknown`: an inventory snapshot is not a Helper-authored Commit proof. The user must acknowledge a determinate reconciliation before another Prepare can begin.
- The previous state being observed is reported separately and requires a fresh Prepare; it is not treated as proof that no mutation occurred.
- Added localized status messages and unit-test source for desired/previous/indeterminate outcomes.

## Product and security boundaries

- APP remains the only per-App enable/disable entry point.
- Plugin remains limited to plugin management and Additional App Association membership.
- No changes to Helper peer authentication, ownership verification, transaction journal/recovery, replay protection, or production release gates.
- No production write gate was opened. No injection, activation, association commit, or uninstall was executed.

## Known boundary

R19 adds client-side read-after-refresh reconciliation only. It does not add a Helper-side durable query-by-request-ID protocol. Therefore, if the fresh inventory is inconsistent, unavailable, or cannot uniquely identify the command target, the result correctly remains indeterminate and the APP toggle stays blocked. Resolving that case requires a separately reviewed Helper status protocol backed by durable transaction evidence.
