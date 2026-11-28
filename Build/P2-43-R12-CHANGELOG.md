# P2-43-R12 Changelog

## Scope

R12 adds a read-only, descriptor-relative filesystem observation and artifact reconciliation layer for the R11 crash-recovery model. It does not execute install, rollback, launchd, Keychain, or provisioning mutations.

## Added

- `HelperInstallerDescriptorFilesystemObserver.swift`
  - Traverses the configured JBROOT and artifact paths using directory file descriptors and `openat`.
  - Uses `O_NOFOLLOW` for root and child path components.
  - Rejects unsafe JBROOT ancestors: non-root-owned ancestors must not be owner-writable; the final JBROOT must match the configured owner UID and must not be group/world writable.
  - Requires artifact parent directories to be owned by the expected owner and not group/world writable.
  - Requires observed files to be regular files, expected-owner-owned, single-link, and not group/world writable. The active-release pointer additionally requires private mode (no group/other permissions).
  - Enforces bounded reads, computes SHA-256 from descriptor-read bytes, and compares inode/device/size/timestamps before and after reading.
  - Distinguishes a missing artifact (`ENOENT` beneath an opened JBROOT) from an unavailable JBROOT; only the former becomes an explicit `.missing` observation.
  - Reads the optional `Library/FilterKit/Helper/active-release.json` pointer as a hint, not as a trust anchor.
- `HelperInstallerArtifactReconciliationBackend`
  - Observes active, staged, and previous artifact locations supplied by the trusted caller.
  - Converts observations into the existing `HelperInstallerRecoverySnapshot` and `HelperRootReleaseRecoveryAssessment` inputs.
  - Accepts an active release identifier only when the pointer's complete artifact-hash map matches the descriptor-observed active files.
  - Derives a staged release identifier only when a `HelperRootReleaseSet.Verified` release hash map exactly matches the observed staged files.
- `HelperRootReleaseSet.activeReleasePointerPath` constant.
- Host smoke, static audit, and XCTest model/path-policy coverage.

## Security boundaries

- The observer is strictly read-only. It has no rename, unlink, mkdir, chmod, file-write, launchd, or Keychain operation.
- `active-release.json` is not signed and is not trusted independently. It is only accepted as an active identity hint after its three hashes match independently observed active artifact bytes; the signed `HelperRootReleaseSet.Verified` remains the release authority.
- Active/staged/previous relative path maps are supplied by a trusted caller. R12 does not define or activate a production release-directory layout.
- Service/launchd state still comes from a separate authenticated service observer.
- No production recovery executor or privileged filesystem backend is enabled.
