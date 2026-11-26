# P2-04 Changelog

- Added intent-only Helper IPC models for per-App Filter.plist mutation preparation.
- Added Helper-side ownership/package/manifest/hash authorization and in-memory plist + manifest preparation.
- Added dispatcher handling with authenticated envelope binding, freshness, replay protection, clean-recovery requirement and audit events.
- Registered the read-only authorizer in the Helper runtime.
- Kept all production mutation/deployment release gates closed.
- Added request-shape tests and P2-04 security/validation notes.
