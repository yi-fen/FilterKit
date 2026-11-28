# P2-44-R1 — Production Write Gate Inventory & Capability Matrix

Status: **inventory only; no production write gate is opened in R1**.
Baseline: P2-43-R17 (`FilterKit-P2-43-R17-Source.zip`, SHA-256 `f1f190ba3d121301f43602ff9838686b12b6f69aba6bb56862cfef7bc221ea73`).

## 1. Scope and terminology

This inventory distinguishes three kinds of writes:

1. **Product mutation writes** — privileged changes to ElleKit/RootHide plugin files, `Filter.plist`, Manifest topology, app activation state, Helper installation/release files, or uninstall state. These are the writes P2-44 may progressively release.
2. **Supporting durable-state writes** — journals, ledgers, trusted provisioning state, audit records and app-local operation state needed to make the product safe. Some implementations already write these records; their existence does not mean product mutation is released.
3. **User-directed export writes** — writing an already-created backup archive to a user-selected/export location. This is not plugin installation or restore and must not be confused with privileged mutation.

A capability marked `closed` remains closed even if its UI, request model, authorizer, transaction implementation, or dry-run exists. A capability marked `partial` has preparatory/read-only components but no released end-to-end production mutation path.

## 2. Capability matrix

| ID | Capability | Current source evidence / entry point | Current state | Required release evidence before opening |
|---|---|---|---|---|
| W-01 | Helper release install / upgrade / activation / rollback | `HelperInstallerExecutionGate`; `HelperTrustedInstallerCoordinator`; `HelperRequestDispatcher.executionReleased`; signed release and R10–R17 recovery components | **closed**; generated plans remain execution-disabled and the root installer adapter is unavailable | Darwin root installer adapter; signed artifact/provenance verification; shared transaction lock; durable Journal; Active/Staged/Previous layout; crash/recovery device acceptance; operator approval; launchd lifecycle validation |
| W-02 | Plugin first injection / deployment batch | `HelperDeploymentCoordinator.executionReleased`; `HelperRequestDispatcher.executionReleased`; `HelperProductionDeploymentBackend.executionReleased`; `HelperDeploymentCoordinator.submitBatch/submit` | **closed**; dispatch and backend release switches are false | RootHide/ElleKit device-verified deployment strategy; authenticated Helper identity; ownership/package-manager proof; dylib/plist/Manifest consistency; staging and three-file transaction; durable recovery; audit barrier; explicit confirmation; end-to-end device acceptance |
| W-03 | Per-App plugin enable / disable | `PluginToggleReleaseGate.productionMutationReleased`; `HelperDeploymentCoordinator.appPluginActivationCommitReleased`; `HelperRequestDispatcher.executionReleased` (activation commit route) | **closed**; readiness evaluation cannot independently release mutation | Verified device-specific Filter.plist strategy; Helper identity; clean recovery Journal; writable audit sink; FilterKit ownership and pair verification; target App availability; per-App state transaction; device acceptance; user confirmation |
| W-04 | Additional App Association add / remove | `HelperDeploymentCoordinator.pluginAssociationCommitReleased`; `HelperRequestDispatcher.pluginAssociationCommitReleased`; `HelperPluginFilterConfigurationTransaction` | **closed**; independent association commit gates are false | Fixed Owner/topology invariants; canonical Bundle ID validation; fresh ownership and identity proof; transactional Filter.plist + Manifest update; audit acceptance before write; crash recovery; RootHide device acceptance |
| W-05 | Plugin uninstall (FilterKit-owned only) | `HelperRequestDispatcher.pluginUninstallExecutionReleased`; `HelperThreeFileUninstallTransaction`; `HelperPluginUninstallAuthorizer` | **closed**; transaction and authorizer exist, but dispatcher release switch is false | Fresh ownership proof; exact dylib/plist/Manifest hashes; package-manager exclusion; all App targets disabled; no pending journal; durable three-file quarantine transaction; recovery acceptance; device test; explicit operator confirmation |
| W-06 | Backup export | `FilterKitBackupService.makeBackup`; `PluginsView` writes generated archive atomically to a temporary file | **partial / user-directed export path exists**; not a privileged plugin mutation | Confirm export includes only FilterKit-owned records and all required topology/state; secure temporary-file handling; user-selected destination/share workflow; verify archive round-trip and no external-source takeover |
| W-07 | Backup restore / plugin re-deployment from backup | `FilterKitBackupService.inspectBackup` and `restorePreview` | **closed for mutation**; inspection and preview exist; no production restore writer is evidenced in this service | Restore eligibility policy; installed-associated-App filtering; conflict/package-manager checks; immutable Fixed Owner; staged payload verification; normal deployment transaction and all W-02 gates; full restore/rollback device acceptance |
| W-08 | Plugin association/topology read and inventory | `PluginScanRegistry`; `ReadOnlyPluginAssociationReader`; shared scan snapshot | **read-only**; not a write capability | No release action. Preserve single inventory/scan path and do not introduce a parallel scanner/cache as part of enabling writes. |

## 3. Cross-cutting execution gates observed in R17

The following independent switches are explicitly false in the source baseline:

- `HelperRequestDispatcher.executionReleased`
- `HelperRequestDispatcher.pluginAssociationCommitReleased`
- `HelperRequestDispatcher.pluginUninstallExecutionReleased`
- `HelperDeploymentCoordinator.executionReleased`
- `HelperDeploymentCoordinator.pluginAssociationCommitReleased`
- `HelperDeploymentCoordinator.appPluginActivationCommitReleased`
- `HelperProductionDeploymentBackend.executionReleased`
- `PluginToggleReleaseGate.productionMutationReleased`

Additionally, installer plans/manifests are constructed with `executionEnabled == false`, and `HelperInstallerExecutionGate` requires the plan bit, a root installer, verified provenance, signed artifacts and operator approval.

These switches are independent defense-in-depth boundaries. A future release must not simply flip one constant: the corresponding capability's complete acceptance criteria must be satisfied, and every relevant App-side, IPC dispatcher, Helper coordinator/backend and durable transaction boundary must agree.

## 4. Release sequencing for P2-44

Recommended order, subject to acceptance evidence:

1. **R1 — Inventory (this release):** record every mutation surface, current gate and release criteria. No gate changes.
2. **R2 — Durable Journal production write qualification:** platform-specific atomic persistence, permissions, fsync, corruption and crash tests. This enables supporting state only, not plugin mutation.
3. **R3 — Staged payload write qualification:** isolated staging, no-follow traversal, ownership/mode, hash and signed identity checks.
4. **R4 — Previous-release backup qualification:** verified backup, retention and recovery evidence.
5. **R5 — Active three-artifact transaction qualification:** shared lock, intent-before-side-effect, atomic replacement, rollback and recovery on device.
6. **R6 — Active Pointer production writer qualification:** pointer hash binding and atomic directory-durable replacement.
7. **R7 — Helper install/upgrade/activation release:** only after Darwin launchd, signed artifacts and device acceptance; W-01.
8. **R8 — Plugin first injection/deployment release:** W-02, independently gated.
9. **R9 — Per-App enable/disable release:** W-03, independently gated and device strategy verified.
10. **R10 — Additional App Association release:** W-04, preserving Fixed Owner semantics.
11. **R11 — Uninstall release:** W-05, only for FilterKit-owned plugins and the established three-file transaction.
12. **R12 — Backup restore release:** W-07, using the normal deployment path, never a separate bypass writer.

Backup export (W-06) may be qualified separately because it does not mutate plugin deployment state.

## 5. Non-negotiable invariants during rollout

- Unknown-source and package-manager-owned plugins remain read-only; SHA-256 equality alone is not ownership proof.
- Fixed Owner is immutable. Additional App Associations remain independently enabled/disabled and cannot be promoted to Fixed Owner.
- No direct UI filesystem writes to privileged plugin directories.
- All privileged mutation must pass authenticated Helper IPC, fresh authorization, ownership proof, audit barrier, durable transaction and recovery checks.
- A dirty, missing, corrupt or ambiguous Journal blocks mutation.
- Do not bypass the existing three-file install/uninstall transaction or introduce an alternate mutation path.
- Do not add a second plugin scanner, inventory cache or rescan path.
- A gate is opened only in a dedicated release with platform/device evidence. Host smoke tests and static audits alone are insufficient.

## 6. R1 conclusion

R17 source inspection confirms the product mutation gates listed above remain closed. Some supporting stores and user-directed backup export already perform writes; those are not evidence that privileged plugin mutation is released. R1 changes documentation and audit tooling only. **No production gate constant, manifest execution bit, dispatcher branch, Helper backend, or filesystem mutation behavior is changed.**
