# P2-38-R1 — LaunchServices Proxy Metadata Priority

## Scope

- Use LaunchServices proxy values first for display name, short version, build version, executable name, and icon name.
- Resolve each field independently. If any optional field is unavailable from the proxy, read the app's `Info.plist` at most once and fill only missing fields.
- Keep `applicationIdentifier` and `bundleURL` as required proxy values; do not infer either value.
- Keep `CFBundleExecutable` fallback mandatory. `executableName` participates in app-binary identity inspection and plugin pairing; a missing value must remain incomplete rather than being guessed.
- Preserve path-first system/user classification (`/Applications/` and `/System/` only). Ignore LaunchServices `applicationType` for this classification.
- Keep the existing non-Objective-C fallback implementation.

## Local diagnostics

The LaunchServices scan emits one local-only `NSLog` record with elapsed time, proxy count, valid bundle identifier count, proxy selector calls/hits, Info.plist read count, and executable-name completeness. No data is uploaded.

## Validation performed

- `swiftc -parse` across app, helper, and unit-test Swift sources.
- `Build/Host/run-p238r1-proxy-metadata-smoke.sh` static invariant audit.
- Existing `Build/Host/run-p237-activation-host-smoke.sh` was also run. It reports 23/24, with the pre-existing `toggle is disabled unless state resolver permits it` check failing. The identical failure reproduces on the unmodified R8 baseline, so it is not attributed to R1.

## Device acceptance still required

On supported RootHide/ElleKit devices, record the R1 diagnostic line for a representative inventory. Verify proxy selector coverage across iOS versions, verify Info.plist fallback count and executable-name completeness, and confirm executable pairing for apps whose proxy omits `executableName`. Do not remove plist fallback until field hit-rate evidence has been collected.

No production write gate is changed by this phase.
