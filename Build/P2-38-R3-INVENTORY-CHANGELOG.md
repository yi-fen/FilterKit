# P2-38-R3 — App Inventory & Plugin Association Reuse

## Changes

- Apps association resolution now consumes `PluginScanRegistry.shared.result` and its existing scan lifecycle. Apps no longer constructs a second `ReadOnlyPluginScanner` or re-walks plugin directories on page entry.
- If the shared plugin snapshot is not ready, Apps asks the registry to start/reuse its existing background scan and waits for the published result.
- A process-wide LaunchServices notification observer listens for `com.apple.LaunchServices.ApplicationsChanged`; it is not installed per row or per page instance.
- Notification bursts are debounced by 500 ms. The callback only schedules the shared inventory cache's stale refresh.
- Stale refresh bypasses the 60-second TTL while retaining the previous successful list and synchronous mirror. A successful complete scan replaces the snapshot; a failed scan retains the old snapshot and leaves it stale for retry.
- Observer teardown cancels the Darwin notify token.

## Preserved constraints

- Existing 60-second in-memory TTL, in-flight request sharing, detached/background scan, prewarm, and deduplication/sorting remain.
- Explicit `invalidateCache()` retains its prior destructive semantics for callers that intentionally require a cold cache.
- No disk-persisted app inventory, additional TTL layer, bulk icon decoding, or production write path was added.
- PluginScanRegistry's generation tracking, successful-snapshot retention, Helper attestation, and retry monitor were not redesigned.

## Validation

- Host static audit and Swift syntax parse are run by `Build/Host/run-p238r3-inventory-smoke.sh`.
- XCTest coverage added for successful stale replacement and failed-refresh snapshot retention/retry.
- Actual XCTest execution, iOS SDK compilation of Darwin notify integration, and RootHide device notification behavior require macOS/Xcode and a supported device; they are not claimed by the host audit.
