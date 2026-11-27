# P2-39-R3-R1 — Directory Enumeration Accounting Audit

## Scope

Audit and correct the meaning of directory enumeration counters, and fix the first-tap blank diagnostics export.

## Findings

1. `PluginDirectoryLocator.inspectCandidate` enumerates readable third-party candidate directories while constructing an environment assessment. This can run from Home, Settings, Helper preflight, and PluginScanRegistry environment assessment.
2. `ReadOnlyPluginScanner.scan` separately enumerates a directory only when no reusable `entryNames` listing is present in the assessment.
3. Before this revision both paths incremented the same `directoryEnumerationCount`. Consequently the observed increase from 2 to 6 did **not** prove that the scanner re-enumerated four times or that APP navigation caused four inventory scans. It conflated environment-probe I/O with inventory-scan I/O.
4. The scanner's reuse path already consumes `PluginDirectoryCandidate.entryNames`; that behavior is retained.
5. Export previously serialized the currently persisted log file. A first export could therefore produce a blank file if no summary line had yet been appended. Export now records fresh App and Plugin snapshots first, then reads the serial diagnostics queue (which drains preceding appends) and writes a non-empty fallback report if there are no persisted events.

## Changes

- `directoryEnumerationCount` now means actual fallback directory enumerations performed by `ReadOnlyPluginScanner` only.
- Added `environmentProbeEnumerationCount` for candidate directory listings performed by `PluginDirectoryLocator`.
- Runtime Diagnostics UI and log summaries expose both counters with distinct names.
- Added/updated locator tests to assert probe enumeration and inventory enumeration are separate, and scanner reuse does not add an inventory enumeration.
- Export now snapshots both diagnostics domains at tap time, waits behind queued writes via the existing serial queue, and always creates a non-empty export artifact.
- No scanner, Registry, cache, association, Helper identity, or activation behavior was changed. No new scan path was introduced.

## Validation performed

- `swiftc -parse` across all Swift files under `Sources` and `Tests`: PASS.
- `Build/Scripts/verify-project-config.sh`: PASS.
- `Build/Scripts/verify-localizations.py`: BLOCKED by an existing parser incompatibility with block comments in `Resources/en.lproj/Localizable.strings` (line 277); this is unrelated to the added keys. Both new keys were added to English and Simplified Chinese catalogs.
- Xcode/iOS SDK build and XCTest execution: NOT RUN (not available in this host environment).
- Device export behavior and counter values: require a new signed install and on-device retest.

## Device acceptance

1. Open Runtime Diagnostics and tap Export immediately on first entry; exported file must contain current App and Plugin summary lines, or a non-empty explicit no-events message.
2. Open Home/Settings and revisit APP. Observe `environment_probe_directory_enumerations` separately from `inventory_directory_enumerations`.
3. With a valid Registry snapshot, APP re-entry must not increment `scans` or `inventory_directory_enumerations`.
4. A scanner run that consumes `entryNames` should increment `directory_listing_reuses`, not `inventory_directory_enumerations`.
5. Explicit refresh may cause one inventory scan; Helper attestation retry must not cause an inventory scan.
