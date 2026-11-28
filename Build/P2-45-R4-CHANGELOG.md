# P2-45-R4 — RootHide Device End-to-End Acceptance

- Added a read-only on-device evidence collector for a real Darwin/RootHide device.
- Collector requires explicit JBROOT and report path; refuses non-Darwin hosts, non-root execution, and report paths inside JBROOT.
- Collector records device OS/build, boot-session UUID, UID/GID, supplied deployment path metadata, optional launchd job visibility, and optional codesign diagnostics.
- Added a 12-row device acceptance matrix covering signed Helper identity, launchd, authenticated IPC, filesystem boundaries, Darwin atomic replacement, three-file transaction, interruption, reboot recovery and rollback.
- Added Host qualification runner and static checks ensuring production write gates remain closed.
- No production execution gate or live filesystem behavior was enabled or altered.

Status: **DEVICE_ACCEPTANCE_PENDING / HOST_QUALIFICATION_ONLY**. This Linux environment cannot execute the device-side tests.
