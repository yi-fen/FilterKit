# P1-29 — Root-side Production Backend Preflight

## Delivered

- `HelperStagingPayloadReader` reads staging payloads below a fixed root using fd-relative `openat` traversal and `O_NOFOLLOW` for every path component and final file.
- `HelperProductionDeploymentBackend` is the concrete Helper-side implementation of `HelperDeploymentPipelineBackend`.
- Route inspection now derives manifest existence from the target directory and package-manager ownership from configured root-owned dpkg `info/*.list` files. A present manifest is considered FilterKit-owned only after the existing Manifest + deployed dylib + plist + Mach-O identity verifier succeeds and its Plugin UUID matches the batch.
- First-install preflight reads both real staging files, checks their requested SHA-256 values, parses the plist, parses Mach-O slices, computes the binary identity fingerprint, validates the root-side package ownership proof, and binds the hard-bound/soft association metadata into a planned Schema 3 manifest digest.
- Update preflight verifies the currently deployed FilterKit manifest and payloads before preparing new-payload plans. It does not trust metadata from the App to re-establish the hard binding.
- `HelperDeploymentBatchMetadata` adds the source App's hard-bound Bundle ID and soft associations to the canonical batch digest. Metadata tampering invalidates the batch digest. Older payloads without the optional metadata still decode, but production first-install authorization rejects missing metadata.
- `HelperDeploymentCoordinator` can encode and submit the metadata as part of the same deployment batch.
- `HelperRuntime` now registers the concrete backend and pipeline. The staging owner UID is explicit in `HelperDeploymentManifest`; it is no longer guessed from the allowed client UID list.

## Deliberately not released

The concrete backend is currently a **read-only authorization/preflight backend**. Its `execute` method always throws `executionNotReleased`.

Two integrity gaps must be closed before writes can be enabled:

1. First install currently needs the Root-owned Schema 3 Manifest to be committed atomically with the new dylib and plist. The existing executor transaction journals only the paired payload files; creating the Manifest before the pair can leave an orphan Manifest after a crash, while creating it after the pair can leave deployed but unowned files after a crash.
2. Update currently replaces a dylib as well as a plist, and must update the Root-owned Manifest hashes and identity in the same recoverable transaction. The existing executor rejects an existing dylib and the current journal/recovery schema tracks only the previous plist.

Until a three-file transaction (dylib + plist + ownership Manifest), backup/recovery model, and crash simulation are implemented, the backend must not write the target plugin directory. The previous `HelperFirstInstallManifestBootstrap` remains available for isolated tests but is not invoked by this production backend.

## Safety invariants

- No shell, dpkg command, arbitrary absolute path from IPC, symlink traversal, or target-App Bundle modification.
- Package ownership database is read-only. Missing/unreadable dpkg evidence is `unknown`, never `unowned`.
- Existing plugin ownership is proven from the root-owned manifest and deployed bytes, not from filename or directory alone.
- `HelperProductionDeploymentBackend.executionReleased == false`.
- Dispatcher and App-side release gates remain false; deployment manifest templates remain disabled.
- Plugin deletion remains unavailable.
