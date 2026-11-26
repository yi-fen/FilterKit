# P2-17 — PID Generation Verification

## Scope
P2-17 adds a Darwin process-generation snapshot using `proc_pidinfo(PROC_PIDTBSDINFO)` and `pbi_pidversion`. The peer identity provider now performs this sequence on the same accepted socket: LOCAL_PEERTOKEN snapshot → PID generation read → `csops(CS_OPS_CDHASH)` → PID generation read → LOCAL_PEERTOKEN snapshot. Both snapshots must match; process-generation reads must return the exact `proc_bsdinfo` structure size and a non-zero version.

Darwin transport acceptance now requires both a full SHA-256 digest of LOCAL_PEERTOKEN and a non-zero PID generation value. Missing, inaccessible, partial, zero, or changed process-generation evidence is rejected (fail closed). No PID-only fallback is introduced.

## Limitations / verification required
This workspace was processed on a Linux host. The Darwin-only `proc_bsdinfo`, `PROC_PIDTBSDINFO`, `pbi_pidversion`, and `proc_pidinfo` branch cannot be SDK-typechecked or executed here. Availability and permissions on the target iOS/RootHide environment must be verified with the actual deployment SDK and device. In particular, `proc_pidinfo` access to the connecting app process may be restricted; such a restriction will cause authentication to fail closed. Host tests validate only the pure comparison policy (including a 10,000-iteration concurrent policy stress test), not kernel PID-reuse behavior or Darwin authentication under real process churn.

## Safety
All production deployment and plugin-association release gates remain false. P2-17 does not enable filesystem writes, plugin activation/deactivation, or production deployment.
