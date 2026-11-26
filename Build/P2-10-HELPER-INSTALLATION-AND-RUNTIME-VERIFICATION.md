# P2-10 — Helper Installation & Runtime Verification

## Scope and truth boundary

> Permission layout note: the original P2-10 `0700` directory / `0666` socket observation is superseded by P2-11 schema-2 provisioning (`0711` traversal directories and `root:<measured-App-GID> 0660` socket). Use the P2-11 guide and probe for current requirements.

P2-10 adds a **read-only on-device verification probe** and a repeatable evidence checklist. It does not install, repair, start, stop, enable, disable, re-sign, chmod, chown, or remove Helper artifacts. It does not open plugin configuration writes. The probe must be run on the target RootHide device as root after the trusted package installer has installed the artifacts.

## Read-only probe

```sh
sh Build/Device/p210-helper-runtime-probe.sh \
  '<device-verified-jbroot>' \
  '<40-character-helper-cdhash>' \
  '<40-character-app-cdhash>'
```

The probe checks:

- root execution context;
- Helper directory, executable, manifest, and launchd plist type/UID/GID/mode;
- launchd plist syntax and the disabled `Disabled=true`, `RunAtLoad=false`, `KeepAlive=false` state;
- manifest JSON syntax, expected first App/Helper CDHash pins, `executionEnabled=false`, and exact socket path;
- installed Helper CDHash using the platform `codesign` inspection command;
- whether the exact launchd label and socket currently exist, without changing either.

A passing probe is **not** proof of live IPC authentication. The socket is deliberately reported, not automatically accepted: the P2-09 design uses a root-owned `0700` Helper directory and a socket currently configured `0666`. Those permissions may make an App-side connection impossible or expose a broad connection surface depending on the target jailbreak's filesystem and sandbox behavior. Do not loosen directory permissions or change socket mode based on assumptions. Measure App UID/GID, access behavior, peer credentials, and `csops` CDHash retrieval on the actual device, then design a least-privilege access route.

## Required device evidence

1. Record iOS build, RootHide version, ElleKit version, device architecture, verified JBROOT, App UID/GID, Helper UID/GID, and package ownership.
2. Run the probe and retain its complete output.
3. Separately verify the Helper launchd process PID/UID and executable path with read-only process inspection.
4. From the signed App, attempt health IPC with the expected trust pins. Verify correct App accepted and wrong UID/CDHash rejected. Record socket directory traversal and connect results.
5. Verify `getpeereid`, peer PID retrieval, and `csops(CS_OPS_CDHASH)` behavior on the exact iOS build. Failure must fail closed.
6. Confirm the Helper's own CDHash matches the root manifest and AppTrust resource.
7. Confirm no stale socket is removed by the runtime; stale-socket cleanup remains the trusted installer's responsibility.
8. Keep all commit/deployment gates closed. Do not test real plugin mutation until the IPC and recovery evidence has been reviewed.

## Current release gates

The following remain false in source:

- `HelperRequestDispatcher.pluginAssociationCommitReleased`
- `HelperDeploymentCoordinator.pluginAssociationCommitReleased`
- `HelperRequestDispatcher.executionReleased`
- `HelperDeploymentCoordinator.executionReleased`
- `HelperProductionDeploymentBackend.executionReleased`

## Limitations

No target device, signed App/Helper pair, or Xcode/iOS SDK is available in this work session. Therefore no installation, launchd execution, live socket connection, peer credential, CDHash runtime, or ElleKit injection result is claimed. P2-10 is a diagnostic-tool/code-readiness stage, not a completed device validation.
