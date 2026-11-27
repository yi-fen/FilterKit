# P2-39-R2 — Runtime Performance & Single-Scan Device Acceptance

## Status

**Prepared; device acceptance is not yet executed.** This repository was inspected and host-side source checks were run in a Linux environment. A RootHide/ElleKit device, macOS, Xcode, and Apple SDK are not available in this execution environment. Do not interpret this document or the static checks as device measurements.

## Fixed architecture constraints

- One App inventory entry point: `CachedAppDiscoveryProvider`.
- One plugin inventory entry point: `PluginScanRegistry.shared`.
- APP, AppDetail, and Plugins consume the published inventory snapshot; they must not create a `ReadOnlyPluginScanner`.
- The plugin directory assessment enumerates each readable third-party candidate once and passes `entryNames` to `ReadOnlyPluginScanner`.
- Attestation IPC is measured separately. An unchanged-file attestation retry must not trigger plugin directory enumeration, Mach-O parsing, plist reads, or SHA-256 recomputation.
- Preserve inFlight coalescing, generation protection, old-snapshot retention, App inventory mirror/TTL/prewarm, and fail-closed Helper identity validation.
- No production write gate changes. No plugin files should be modified for this acceptance.

## Build and test preflight

On a Mac with Xcode and XcodeGen installed:

```sh
cd FilterKit-P2-39-R1-Scan-Reduction
xcodegen generate --spec Project.yml
xcodebuild build -project FilterKit.xcodeproj -scheme FilterKit \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
```

For a configured test device, use the runner:

```sh
FILTERKIT_DEVICE_UDID='<device-udid>' \
  Build/Host/run-p239r2-runtime-preflight.sh
```

The runner generates the Xcode project if needed, performs the generic iOS build, and runs the `FilterKit` test scheme on the specified device, writing an `.xcresult` bundle under `Build/DeviceAcceptance/Results/`.

## Device setup

1. Use a dedicated RootHide + ElleKit test device. Record iOS version, device model, RootHide version, ElleKit version, FilterKit build SHA, and whether Helper is installed/trusted.
2. Build/install a **Debug** app so the local diagnostic `NSLog` summary is available.
3. Do not toggle plugins, alter filter rules, edit plugin files, or open the production write gate during this scan-only acceptance.
4. Open macOS Console (or the device log stream) and filter for:

   `FilterKit][PluginInventory][P2-39-R1]`

5. Keep the app in foreground during each navigation step. Capture a diagnostic summary after each step.

## Acceptance scenarios

Counters are cumulative process-local counters. Compare before/after values; do not assume they reset when a view changes.

| ID | Action | Required observation |
|---|---|---|
| R2-01 | Fresh launch, wait for initial plugin inventory and Helper attestation attempt to settle | `scans` increases by exactly 1. `directory_enumerations` reflects one listing per readable third-party candidate inspected; the selected candidate is consumed through `directory_listing_reuses`, not re-enumerated by the scanner. |
| R2-02 | Leave APP page and enter it a second time with a successful registry snapshot | `scans` delta = 0; `directory_enumerations` delta = 0. `association_snapshot_consumptions` may increase. |
| R2-03 | Open AppDetail, return, open Plugins, return to APP | `scans` delta = 0 and `directory_enumerations` delta = 0 for navigation alone. |
| R2-04 | Wait for a Helper-unavailable retry interval (at least 30 seconds) with unchanged plugin files | `attestation_only_retries` may increase; `scans` and `directory_enumerations` must not increase. Attestation counters are independent. |
| R2-05 | Wait past the configured attestation freshness period with unchanged file observations | Attestation may be repeated from the same snapshot; `scans` and `directory_enumerations` remain unchanged. |
| R2-06 | Observe a real file metadata change | Do not modify a production plugin to force this test. Use a dedicated disposable test fixture/device image. If a metadata change is observed, `inventory_refresh_file_changes` and `scans` should each increase once for the coalesced refresh; verify generation protection and snapshot retention. |
| R2-07 | Simulate Helper unavailable, then restore Helper reachability | No inventory rescan solely due to IPC failure/recovery. Identity remains fail-closed until a fresh valid attestation is received. |
| R2-08 | Cause an inventory refresh failure in a disposable fixture | Previous successful snapshot remains visible; failure does not clear the list. |

## Pass criteria

- R2-01 through R2-05 pass on a real RootHide/ElleKit device.
- No navigation-only scan is observed after the first successful plugin snapshot.
- No unchanged-file attestation retry causes a plugin directory enumeration.
- Attestation latency is reported separately from environment assessment and plugin inventory scan latency.
- No plugin file mutation, activation, injection configuration write, or release-gate change occurs.

R2-06 and R2-08 require a disposable test fixture and are optional only if the device cannot safely provide one; otherwise record them as **Not Run**, not Pass.

## Result record

Record one row per run:

| Field | Value |
|---|---|
| Date/time | Not run |
| Device / iOS | Not run |
| RootHide / ElleKit | Not run |
| FilterKit build SHA | Not run |
| Helper trust state | Not run |
| Scenario | Not run |
| `scans` before → after | Not run |
| `directory_enumerations` before → after | Not run |
| `directory_listing_reuses` before → after | Not run |
| `attestation_only_retries` before → after | Not run |
| `inventory_refresh_file_changes` before → after | Not run |
| Environment assessment ms | Not run |
| Plugin directory scan ms | Not run |
| Attestation attempts / outcomes / ms | Not run |
| Result / evidence | Not run |

## Interpretation limits

- The `directory_enumerations` counter is instrumented around FilterKit's `FileManager.contentsOfDirectory` calls in the inventory path; it is not a global kernel filesystem syscall counter. Use Instruments File Activity or equivalent if system-wide I/O proof is required.
- Metadata observations (size, modification date, file number) are not cryptographic change detection. A file modified while preserving all observed metadata may not be detected immediately; do not claim otherwise.
- Static source checks and `swiftc -parse` do not substitute for XCTest execution, iOS SDK compilation, or device acceptance.
