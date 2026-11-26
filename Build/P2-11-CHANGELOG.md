# P2-11 Changelog

- Replaced the Helper listener's `0666` socket default with `0660`.
- Added installer-provisioned `socketGroupID`; Helper assigns the socket group before applying its mode.
- Changed the private Helper directory from `0700` to traverse-only `0711`; sensitive manifest/audit files remain `0600`.
- Added fail-closed validation for missing/zero socket group IDs.
- Updated provisioning generator to require `--socket-gid` explicitly and write it to both provisioning bundle and root manifest.
- Added a read-only RootHide IPC permission probe and device-validation guide.
- Kept all execution/commit gates closed.

- Bumped Helper deployment manifest and installer provisioning bundle to schema 2 so older manifests without a socket GID fail closed.
- Added a traverse-only `JBROOT/Library/FilterKit` parent artifact to the lifecycle plan.
