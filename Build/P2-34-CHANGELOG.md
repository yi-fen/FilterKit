# P2-34 Changelog

- Implemented Home device overview and Filter health summary.
- Moved inventory statistics out of Settings; retained low-level diagnostics.
- Enforced App-detail-only first-time dylib/plist import entry.
- Removed dylib/plist import, bulk selection, uninstall, and activation controls from Plugins.
- Kept backup export and `.filterkitbackup` import/restore review in Plugins.
- Updated plugin detail association presentation for hard-bound and soft-associated Apps.
- Added P2-34 product architecture audit and updated historical P2-33/P2-32 audits to the new page boundaries.
- Kept all production mutation gates closed.
