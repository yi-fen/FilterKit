# P2-17 Changelog

- Added exact-size `proc_pidinfo(PROC_PIDTBSDINFO)` PID-generation reads.
- Bound the CDHash lookup between matching PID-generation snapshots and matching LOCAL_PEERTOKEN snapshots.
- Darwin client/server transport now requires both audit-token digest and non-zero PID generation evidence.
- Added fail-closed generation comparison policy and unit tests for stable, missing, zero, and changed generation values, plus a 10,000-iteration concurrent policy stress test.
- Documented Darwin SDK/device validation limitations; production write gates remain disabled.
