# P2-05 Changelog

- Added `HelperPluginFilterConfigurationTransaction`, a dedicated two-file atomic transaction for Filter.plist and `.fk.json` association edits.
- Added staged-file validation, root ownership/mode enforcement, exact old-byte/hash revalidation, two verified backups before replacement, durable phase journal, hash-verified commit, and conservative idempotent recovery.
- Explicitly excludes the dylib from every transaction operation.
- Added read-only startup journal inspection and the `associationTransactionRecoveryRequired` status; pending transactions block normal Helper work.
- Added a root-only crash/recovery XCTest fixture.
- Kept transaction execution disconnected from IPC and all production execution gates closed.
