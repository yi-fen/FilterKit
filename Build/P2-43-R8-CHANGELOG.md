# P2-43-R8 — Trusted Provisioning Persistence and Anti-Rollback

## Scope

R8 turns the R7 signed Provisioning requirement into a concrete persistence boundary while keeping all privileged installer execution disabled.

## Changes

1. Added `HelperVerifiedProvisioningBaseline`. Its initializer is file-private; the baseline is produced by `HelperProvisioningSignatureVerifier.verifiedBaseline(from:)` only after signature verification.
2. Added `HelperRootOwnedProvisioningFileStore` for the two fixed Provisioning leaves. It requires an installer-precreated root-owned `0700` directory, rejects symlink path components and leaf symlinks, writes `0600` temporary files, fsyncs the file, atomically renames within the same directory, and fsyncs the directory. It does not create/chown/chmod the containing directory.
3. Added `HelperProvisioningCheckpointStoring` and an append-only Keychain implementation. Each accepted generation is bound to the SHA-256 digest of the exact signed envelope. A second digest for an already-recorded generation is treated as conflict.
4. Added `HelperTrustedProvisioningStore`. It verifies signatures before trusting persisted payloads, checks monotonic generation + exact digest, and uses a pending intent record to recover an interrupted update.
5. Repin and upgrade now obtain their baseline from the trusted store. `HelperInstallerDryRun` no longer accepts a caller-supplied raw `previousProvisioning` bundle; it requires `HelperVerifiedProvisioningBaseline`.
6. `HelperSignedReleaseRuntimeLoader` now loads Provisioning through the trusted store, so startup also reconciles pending intent and checks the device-local checkpoint.
7. Repin is limited to App CDHash rotation with stable Helper identity and install context. Helper release upgrade may rotate Helper CDHash but must preserve App CDHash, Bundle ID, Team ID, UID/GID pins, jbroot and route paths.
8. Added XCTest coverage for trusted baseline creation, monotonic Repin, same-generation digest conflict, and interrupted checkpoint recovery.

## Safety boundary

- The pending JSON is a recovery marker, not a source of trust. The current and candidate signed envelopes are independently verified.
- If current bytes match neither the previous nor next digest, recovery stops for manual intervention.
- If the device-local checkpoint is newer than the current envelope, startup rejects rollback.
- If a generation is already checkpointed with another envelope digest, startup rejects it.
- The Keychain checkpoint is device-local append-only storage, not a hardware monotonic counter. It does not claim to resist a fully privileged device compromise or device restore that also rolls back Keychain state.
- The POSIX file store assumes the directory has already been created and secured by a trusted installer. R8 does not implement that installer.
- `HelperInstallerExecutionGate` remains unchanged and closed; no install/repin filesystem mutation or launchd operation is exposed to production callers.
