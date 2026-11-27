# P2-39-R3 — Runtime Diagnostics & Performance Verification

## Scope

Adds local, bounded runtime diagnostics and a Settings diagnostics screen. This change is observational only: it does not create a scanner, refresh an inventory, change association behavior, change Helper attestation policy, or open any write/injection gate.

## User-facing behavior

- Settings → Runtime Diagnostics displays process-local counters for App Inventory, Plugin Inventory, Association Snapshot consumption, and Helper Attestation.
- Existing App/Plugin performance summaries are persisted locally as plain text.
- Export Logs uses the iOS share sheet to export a `.log` file.
- Clear Logs removes the two local log files.
- Logs are local-only; there is no telemetry or network upload.

## Storage and retention

The app sandbox path is:

`Library/Application Support/FilterKit/Logs/`

Files:

- `FilterKit.log` — current log, capped at approximately 1 MiB.
- `FilterKit.previous.log` — one rotated prior log.

When the current file would exceed the cap, the prior file is replaced and the current file is rotated. File I/O runs on a dedicated utility queue; append failures are intentionally non-fatal. The log contains aggregate counters and timings, not plugin contents or full filesystem paths.

For Filza, locate FilterKit under its app-data/container browser and open:

`Library/Application Support/FilterKit/Logs/FilterKit.log`

The container UUID differs per installation. Export Logs from Settings is the preferred method because it avoids manually locating the app container.

## Metrics

- App Inventory: page entries, warm inventory entries, Info.plist reads, plugin snapshot hits/misses, icon reads, proxy selector hit rates.
- Plugin Inventory: scan count, environment assessment time, plugin directory scan time, directory enumerations and listing reuse, plugin plist/manifest read counts, changed-file refresh count.
- Identity analysis: in-process plugin identity analysis run count and elapsed time.
- Association: shared snapshot consumption, reader fallback, deferred association count.
- Helper Attestation: attempt outcomes and total attestation time, separated from inventory scan time and in-process identity analysis.

Counters are process-local and reset when the app process restarts. Persisted log summaries remain until rotated or cleared.

## Acceptance checklist

1. Build and install on a RootHide/ElleKit device.
2. Open Settings → Runtime Diagnostics; verify the four metric groups render.
3. Visit APP twice with a warm PluginScanRegistry snapshot. Expected: second entry does not increment plugin inventory scan count or directory enumeration count; snapshot consumption may increment.
4. Trigger Helper attestation retry without changing plugin files. Expected: attestation counters/time may change; inventory scan and directory enumeration counters do not.
5. Explicitly refresh plugin inventory once. Expected: one normal registry refresh path; no additional scanner path.
6. Export Logs and inspect the exported `.log`; confirm AppDiscovery and PluginInventory summaries are present.
7. Clear Logs and confirm the current/previous log files are removed.
8. Verify no plugin files, ElleKit configuration, activation state, association state, Helper identity rules, or Release Gate behavior changed.

## Verification status

Source-level Swift parsing and host-side store smoke checks are performed for this package. An Xcode/iOS build, signed installation, Filza inspection, and device acceptance must be performed on the user's Apple/RootHide device; they are not claimed by this source package.
