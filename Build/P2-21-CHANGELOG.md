# P2-21 Changelog

- Wired the existing bounded, lock-protected `HelperRequestReplayGuard` into the authenticated Unix-domain-socket server.
- Added explicit request freshness policy (inclusive ±120 seconds) and reject stale/future requests before replay-cache insertion.
- Added request-validation diagnostics for accepted and duplicate request IDs.
- Added tests for freshness boundaries, duplicate replay, distinct IDs, and 256-way concurrent duplicate consumption.
- Kept the connection cap, five-second socket timeouts, 96 KiB frame bound, fragmented-read loop, one-request-per-connection behavior, and all production write gates unchanged.
