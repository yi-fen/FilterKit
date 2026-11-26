# P2-13 Changelog

- Added optional strict GID enforcement to `HelperPeerTrustPolicy`.
- Configured the Helper to pin the App peer GID to the installer-provisioned socket group.
- Configured the App to require the Helper peer GID to be root (0).
- Tightened the legacy deployment policy to fail closed if socketGroupID is absent or does not match the kernel peer GID.
- Hardened Darwin CDHash extraction by rejecting all-zero output.
- Added a unit test for same UID/CDHash but incorrect GID rejection.
- Added a RootHide device validation procedure and explicit NOT RUN boundaries.
