# P2-26 Changelog

- Replaced the P2-25 root-peer authorization assumption with the correct App-to-root-Helper model: authenticated maintenance peer must be unprivileged; privileged recovery coordinator still verifies the Helper process runs as root.
- Strengthened capability minting with kernel socket credential equality, valid CDHash shape, session nonce shape, complete Audit Token evidence, PID Generation evidence, explicit confirmation intent, transaction binding, request nonce binding, and bounded lifetime.
- Extended maintenance IPC request/response models with optional Transaction ID and operator-confirmation intent.
- Bound maintenance request nonce to the enclosing envelope request ID and verified the echoed Transaction ID client-side.
- Integrated capability minting into the maintenance recovery IPC dispatcher while leaving actual recovery mutation unreleased.
- Updated P2-25 host smoke and static audit to match the corrected App-peer authorization boundary.
- Added P2-26 IPC smoke and unit-test coverage for missing confirmation, nonce mismatch, unprivileged peer acceptance, root peer rejection, and incomplete kernel evidence.
- Kept all production deployment and plugin-association write gates disabled.
