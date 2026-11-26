# P2-29 — First Device Acceptance & Toggle Dry-Run Boundary

## Purpose

P2-29 prepares the first RootHide device acceptance pass for the first real per-App plugin toggle. It does **not** activate a write path. P2-29 requires observed device evidence before any later release review can consider opening a narrowly scoped mutation path.

> Repository note: this archive already contains a separate historical `P2-29-APP-SCAN-PREWARM-AND-DEB-PROFILE.md` and `P2-29-CHANGELOG.md`. Those files are preserved unchanged. This document identifies the P2-29 device-acceptance workstream and does not overwrite the earlier phase record.

## Acceptance sequence

1. Build and sign the App and Helper on macOS with the intended release identity.
2. Verify both signatures and record App/Helper CDHashes and generation.
3. Install on a disposable RootHide test device; record iOS, RootHide, and ElleKit versions.
4. Verify live App → Helper health IPC and peer UID/GID/CDHash policy.
5. Select one FilterKit-owned test plugin and one **non-system** target App. Record the dylib and filter plist SHA-256 values.
6. With mutation still disabled, validate the proposed target/plugin association and backup/restore preconditions.
7. In a separately reviewed device test build only, observe enable, target-process injection, disable, and target restart behavior. Record evidence; do not infer injection from a successful plist write.
8. Exercise interruption/recovery and confirm durable audit records.
9. Reboot and repeat the identity and disabled-state checks.

The evidence template is `Build/DeviceAcceptance/p229-evidence-template.json`. Validate a completed capture with:

```sh
python3 Build/scripts/p229_device_acceptance.py path/to/device-evidence.json
```

The validator checks completeness, formats, and a 24-hour freshness window. It is **not** a cryptographic attestation mechanism; operator-entered booleans are claims that must be backed by retained device logs, command output, and screen/process observations in the release record.

## Release boundary

All existing production gates remain closed:

- `PluginToggleReleaseGate.productionMutationReleased = false`
- `HelperRequestDispatcher.executionReleased = false`
- `HelperRequestDispatcher.pluginAssociationCommitReleased = false`
- `HelperDeploymentCoordinator.executionReleased = false`
- `HelperDeploymentCoordinator.pluginAssociationCommitReleased = false`
- `HelperProductionDeploymentBackend.executionReleased = false`

No production filesystem mutation, ElleKit filter update, injection, install, uninstall, or recovery write is enabled by this phase. A complete evidence file is necessary but not sufficient: a separate code review must bind the evidence to the exact signed artifacts and authorize a narrow one-plugin/one-target implementation. Never flip a global switch merely because this validator returns COMPLETE.

## Host validation

- `python3 -m unittest Build/scripts/test_p229_device_acceptance.py`
- `python3 Build/scripts/p229_device_acceptance.py Build/DeviceAcceptance/p229-evidence-template.json` must exit 1 (expected fail-closed result).
- Existing P2-28 host smoke and static audit remain applicable.

## Not performed

No Apple signing, Xcode/iOS SDK build, device install, RootHide IPC, ElleKit toggle, real injection, process restart observation, or device recovery test is claimed by this phase. These require the signed build and physical test device.
