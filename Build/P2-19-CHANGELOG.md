# P2-19 Changelog

- Added typed, bounded Darwin peer-identity diagnostic reason codes.
- Added PID Generation, audit session ID, and evidence-presence fields to authentication diagnostics.
- Kept raw Audit Token digest out of logs and diagnostic payloads.
- Added tests for complete/incomplete diagnostic evidence and digest non-disclosure.
- Added P2-19 static gate audit (12 checks).
- No production write gates changed; all remain disabled.
