# P2-38-R1 Change Log

- Changed LaunchServices metadata resolution to query proxy values first for localized name, short version, build version, executable name, and icon name.
- Added independent per-field Info.plist fallback, sharing at most one plist read per app and preserving proxy values when only another field is missing.
- Kept `applicationIdentifier` and `bundleURL` mandatory from the LaunchServices proxy.
- Kept `CFBundleExecutable` fallback mandatory; no executable-name inference was introduced.
- Kept path-first system/user classification exactly as before; LaunchServices `applicationType` remains ignored.
- Added offline Objective-C proxy-stub tests for absent executable selector fallback and the complete-proxy no-plist fast path.
- Added local-only scan metrics for elapsed time, proxy count, valid bundle IDs, selector calls/hits, plist reads, and executable-name completeness.
- No app inventory persistence, cache lifecycle changes, icon loading changes, association changes, or production mutation gate changes.
