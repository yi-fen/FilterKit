# P2-39-R1 — Runtime Performance Profiling & Single-Scan Acceptance

## Baseline

Baseline archive: `FilterKit-P2-38-R4-Performance-Diagnostics.zip`  
Baseline SHA-256: `c026c49fbcbeed9aea2b295a682db14cf7203cd7a4ebf9dd8543a1e6e8a126a8`

## Source findings and changes

1. `AppsViewModel.loadAssociationsFromSharedSnapshot()` consumes `PluginScanRegistry.shared.result`; it does not instantiate `ReadOnlyPluginScanner` or rebuild `ReadOnlyEnvironmentProvider.makeDiagnosticReport()`.
2. `PluginScanRegistry.startScan()` remains the only plugin inventory scan entry. It creates the scanner, obtains the read-only environment assessment, and calls `scanPlugins()`.
3. Tightened `loadIfNeeded()` to return when a successful `result` already exists. This closes a navigation-triggered rescan path for consumers such as App Detail that call `loadIfNeeded()` from `.task`.
4. Added process-local profiling that keeps three costs separate:
   - environment / plugin-directory assessment;
   - plugin directory enumeration and Mach-O/plist/hash scan;
   - Helper identity attestation IPC, with verified/rejected/unavailable/error outcomes.
5. Added counters for shared association snapshot consumption and the exceptional app-inventory snapshot fallback in `ReadOnlyPluginAssociationReader`.

## Acceptance invariants

- One plugin inventory scan entry: `PluginScanRegistry.startScan()`.
- APP association consumes `PluginScanRegistry.shared.result`.
- APP page does not construct a scanner or rebuild the environment report.
- `loadIfNeeded()` does not start a new scan when a successful snapshot exists.
- Helper attestation duration is reported separately from plugin directory scan duration.
- Diagnostics are process-local and Debug-log only; no persistence or upload.
- Existing in-flight sharing, generation protection, failed-scan snapshot retention, attestation freshness monitoring, and retry policy remain unchanged.

## Host validation

`Build/Host/run-p239r1-single-scan-acceptance.sh` performs full Swift parser validation and static source acceptance checks. The current run passed 14/14 checks. The prior R1, R2, and R3 smoke audits passed 8/8, 10/10, and 12/12 respectively.

The R4 smoke script did not finish within the host command time limit during this run; its earlier R4 audit result is recorded in the baseline report, but it is not counted as a fresh P2-39-R1 execution result.

## Device profiling procedure

On an Apple device build with Debug diagnostics enabled:

1. Clear the Xcode device log view (no app data reset is required).
2. Launch FilterKit and allow the Plugins page / prewarm path to complete one inventory scan.
3. Open Apps, open an App Detail, return, and enter Apps again without pressing refresh.
4. Filter logs for `[FilterKit][PluginInventory][P2-39-R1]` and `[FilterKit][AppDiscovery][R4]`.
5. Confirm `scans` does not increase during warm navigation; `association_snapshot_consumptions` increases; `association_reader_fallbacks` remains zero; and no new plugin directory scan duration is recorded.
6. Separately record `environment_assessment_ms`, `plugin_directory_scan_ms`, and `attestation_ms`. Do not add attestation time to directory scan time.
7. Press the explicit Plugins refresh control once. Confirm exactly one new inventory scan starts and the previous snapshot remains visible until a successful replacement.

## Not yet validated

This Linux host has Swift 6.2.1 but no Xcode, Apple SDK, UIKit runtime, or RootHide/ElleKit device. XCTest execution, iOS target build/typecheck, real Helper IPC measurements, actual filesystem I/O counts, and device timing distributions remain pending. Static audits do not establish runtime performance.

Production write Gate remains closed.
