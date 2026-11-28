# P2-45-R3 — RootHide Filesystem Production Qualification

## Scope

R3 qualifies the existing descriptor-relative filesystem observer and the three-artifact activation executor at source/Host level. It does not enable production writes and does not claim a RootHide device qualification.

## Added

- `Build/scripts/p245_r3_filesystem_smoke.swift`: 24 runtime assertions against the production `HelperInstallerDescriptorFilesystemObserver` implementation (compiled from its production source through the observer type boundary).
- `Build/scripts/p245_r3_filesystem_audit.py`: 24 source-level security and durability checks for observer and activation executor.
- `Build/scripts/run_p245_r3_validation.sh`: reproducible Host validation entry point.
- `Build/P2-45-R3-VALIDATION-REPORT.md`: results, constraints, and remaining device acceptance requirements.

## Runtime coverage

- Root-owned/private JBROOT test directory and nested artifact directories.
- SHA-256 and file metadata observation for all three release artifacts.
- Missing leaf and missing parent classification.
- Absolute path, traversal, empty component, backslash, and NUL rejection.
- Leaf and intermediate symlink rejection.
- Hard-link, FIFO, wrong-owner file/directory, group-writable file, writable directory, and writable root rejection.
- Private-file permission checks and maximum artifact size enforcement.

## Production source changes

No production Swift source was changed in R3. The existing observer/executor behavior was qualified with a Host harness and static audit. This avoids changing security-sensitive filesystem code without Darwin/RootHide runtime evidence.

## Release gates

All production write gates remain closed. R1 still requires Apple SDK build and signed App/Helper artifacts; R2 still requires real Darwin peer-credential/CDHash/XPC-or-socket runtime evidence; R3 requires execution on an actual RootHide device before it can be considered production-qualified.
