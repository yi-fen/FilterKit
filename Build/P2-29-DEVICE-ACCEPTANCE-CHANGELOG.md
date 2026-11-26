# P2-29 Device Acceptance Changelog

- Added a manual RootHide device-acceptance evidence template for signed App/Helper identity, live IPC, ElleKit enable/disable observation, actual process injection, restart behavior, recovery, and audit persistence.
- Added a read-only validator with schema, hash-format, timestamp-freshness, and required-check validation.
- Added negative tests proving empty, synthetic, stale, incomplete, and malformed evidence is rejected.
- Preserved all existing production mutation and Helper execution/commit release switches as `false`.
- Preserved the archive's earlier P2-29 App-scan/DEB-profile documents; this workstream uses a distinct document name to avoid overwriting historical content.
