# P1-38 — Root Helper Multi-Directory Atomic Activation

## Delivered

Adds `HelperRootAtomicActivationExecutor`, a standalone root-side transaction primitive for the three P1-37 release artifacts:

- `usr/libexec/filterkit-helper` (root:root, 0755)
- `Library/FilterKit/Helper/Deployment.json` (root:root, 0600)
- `Library/LaunchDaemons/cn.yfen.filterkit.helper.plist` (root:root, 0644)

Before touching destinations it re-runs `HelperRootReleaseSet.verify`, requiring the exact three artifact paths, matching SHA-256 inventory, the provisioned JBROOT/route, a disabled deployment manifest, and a disabled/non-auto-starting launchd plist. The root directory and each destination parent are opened component-by-component with `openat`/`O_NOFOLLOW`; parents must be root-owned directories and not group/world writable (the sticky root-owned system temp ancestor is allowed for isolated tests). Existing destinations must be root-owned regular files and match the caller's explicit previous-hash inventory. First install therefore refuses any pre-existing destination; upgrade refuses any unexpected bytes.

The executor stages each file in its own destination directory, fsyncs the file and parent, durably journals phase/progress, preserves previous files under transaction-specific names, and activates with no-replace rename semantics. It verifies the installed hashes before committing. A simulated interruption can be injected after each completed artifact activation.

`recover()` is intentionally conservative: it rolls back only when every observed destination and backup matches the transaction's exact old/new hashes. Unknown bytes, missing previous content, or unproven backup state stop at `manualIntervention`. A journal already marked committed is finalized only after all three current hashes are reverified. The executor never enables or bootstraps launchd.

## Security / integration boundary

This is a standalone low-level primitive and is not connected to HelperRuntime, IPC, `HelperProductionDeploymentBackend`, or the release execution gate. `executionEnabled=false` remains unchanged. It does not verify Apple code signatures, CDHash, notarization, or publisher provenance; SHA-256 is byte identity only. The journal is root-owned and mode 0600 but is not MAC-signed and has no hardware anti-rollback counter. The transaction coordinates three independent directories; it is crash-recoverable, not a single kernel-atomic operation across all three paths. Launchd service activation and device validation remain out of scope.

## Validation

`Build/Scripts/p1-38-root-activation-smoke.swift` exercises a private root-owned sandbox: release-set verification, first install, crash injection after the second artifact, hash-checked rollback, subsequent upgrade, and journal cleanup. This is a Linux host smoke test, not a Darwin/iOS or RootHide device test.
