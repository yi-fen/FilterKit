# P2-33 Changelog

- Added bounded Mach-O inspection to read-only plugin inventory.
- Added CodeDirectory CDHash, identifier, Team Identifier, flags and platform extraction.
- Populated plugin identity and SHA-256 fields instead of leaving third-party metadata blank.
- Improved Filter plist display for Bundles, Executables, Classes and Mode, including boolean Mode values and retained non-string entries.
- Added Filter inventory and ElleKit profile diagnostics to Settings.
- Added FilterKit main executable identity diagnostics to Settings.
- Added host identity smoke and static safety audit.
- Kept all production mutation and deployment release gates closed.
