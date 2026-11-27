# P2-38-R4 — Performance Metrics & Local Diagnostics

## Scope

R4 adds process-local counters and Debug diagnostics for the existing R1–R3 app inventory and icon loading paths. It does not change app classification, LaunchServices field fallback, plugin pairing, plugin activation, injection behavior, or write authorization.

## Metrics

- LaunchServices scan elapsed time, measured from entry into the LS scan through proxy enumeration and metadata processing.
- Proxy inventory count and valid Bundle ID count.
- Per-selector invocation and hit counts for Bundle ID, Bundle URL, and optional metadata selectors; hit rates are emitted as `hits/calls`.
- Actual Info.plist read attempts, counted at the single read function, and `executableName` completeness ratio.
- Icon cache lookups, hits, misses, and hit rate.
- Private API effective image success, empty image, unavailable API, and Objective-C exception outcomes remain separate.
- File icon candidate reads and Asset Bundle lookup attempts.
- APP page appearances, warm inventory entries, PluginScanRegistry snapshot hits/misses, and file icon reads occurring from the second APP page appearance onward.

## Privacy and storage

Counters exist only in process memory. Diagnostic output is Debug-only. No UserDefaults, files, database, network request, telemetry upload, or disk-persisted app inventory was added.

## Validation

- `run-p238r1-proxy-metadata-smoke.sh`: 8/8.
- `run-p238r2-icon-loading-smoke.sh`: 10/10.
- `run-p238r3-inventory-smoke.sh`: 12/12; Swift syntax parse passed.
- `run-p238r4-performance-diagnostics-smoke.sh`: 14/14; full Swift source parse passed.
- Added `testR4PerformanceDiagnosticsTrackSelectorHitsAndSecondEntryFileReads`.

## Platform limitations

This Linux environment has Swift 6.2.1 but no Xcode, Apple SDK, UIKit runtime, or Objective-C runtime suitable for building/running the iOS target. Therefore XCTest execution, Apple-platform type checking, Xcode build, and RootHide/ElleKit device measurements remain pending. Static source audits and Swift parser validation are not substitutes for those checks.

Production write Gate remains closed.
