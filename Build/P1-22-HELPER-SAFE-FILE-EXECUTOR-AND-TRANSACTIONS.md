# P1-22 — Helper Safe File Executor & Paired Deployment Transaction

## 1. Scope

P1-22 adds a narrow, fd-relative file executor for the Helper target and a paired dylib + plist transaction model. It does **not** connect the executor to `FilterKitHelperRuntime`; the runtime continues to reject every `operationRequest`, and `HelperDeploymentCoordinator.executionReleased` remains `false`.

## 2. Files added / changed

- `Sources/Environment/Helper/Execution/HelperOwnershipProof.swift`
- `Sources/Environment/Helper/Execution/HelperSafeFileExecutor.swift`
- `Sources/Core/Models/Helper/HelperDeploymentModels.swift`
- `Project.yml`
- `Tests/UnitTests/HelperSafeFileExecutorTests.swift`
- `Build/Scripts/p1-22-executor-smoke.swift`

The Helper target now compiles the execution module and SHA-256 implementation, but does not invoke it from its request handler.

## 3. Execution boundary

`HelperSafeFileExecutor` accepts exactly two closed plans for the same plugin:

1. `installDylib` → `copyFile` to a safe `.dylib` leaf; target must not exist.
2. `replaceFilterPlist` → `copyFile` to a safe `.plist` leaf; an existing target may be replaced only if it is a root-owned regular file.

Both plans must bind to one `HelperOwnershipProof` with:

- same plugin UUID;
- exact dylib/plist leaf names;
- exact SHA-256 values;
- Manifest Schema >= 3;
- verified Mach-O identity flag.

The proof type is an evidence carrier, not a verifier. A trusted root-owned Manifest/ownership verifier must construct it before any future production call. That verifier is not connected in P1-22. In particular, a newly restored plugin has no pre-existing deployed root-owned Manifest; its first-install provenance/authorization token is a separate unresolved design item. A user-supplied backup or its hash alone is not proof of FilterKit ownership.

## 4. Filesystem protections

- Root process required (`geteuid() == 0`).
- Absolute roots must be clean and fixed at executor construction.
- Directory traversal uses `openat` with `O_DIRECTORY | O_NOFOLLOW` from `/`.
- Staging root and each task directory must be owned by the expected staging UID and have no group/other permission bits.
- Staged leaf files must be regular, owned by the staging UID, mode 0600, and within the configured size limit.
- Target directory must be root-owned and not group/world writable.
- Existing plist must be a root-owned, wheel/root-group regular file with no setuid/setgid bits.
- Destination leaf checks use `fstatat(..., AT_SYMLINK_NOFOLLOW)`.
- Writes go to unique `O_EXCL | O_NOFOLLOW` temporary files, are chmod/chown verified, fsynced, and committed with `renameat`.
- No shell, argv, environment, executable path, recursive deletion, or arbitrary destination path exists in the API.

## 5. Transaction behavior

The executor reads both staged files through directory descriptors, computes SHA-256 over the exact bytes it will deploy, and parses the plist before mutation.

Commit sequence:

1. Create and fsync both target-directory temporary files.
2. Move an existing plist to a transaction-specific backup name.
3. Atomically rename the dylib into place.
4. Atomically rename the new plist into place.
5. fsync the target directory and remove the backup.

If a commit step fails, the executor removes newly committed files and restores the previous plist from the transaction backup. Rollback failure is reported distinctly. A process crash/power loss during the multi-file transaction is not equivalent to a database transaction; recovery journaling and startup reconciliation remain future work. The executor serializes its own in-process transactions, but cross-process coordination must also be guaranteed by the eventual single Helper server dispatch path.

## 6. Deliberately unsupported

- `removeUnmanagedDylib` remains denied by policy; deletion requires a separate ownership-bound authorization path.
- No standalone dylib-only deployment.
- No arbitrary plist path or arbitrary target directory.
- No target App Bundle edits or re-signing.
- No injection engine or runtime loaded-state claims.
- No production Helper request dispatch to this executor.
- No real TweakInject writes from this build.

## 7. Validation

The Linux smoke harness exercises paired install, existing plist replacement, exact byte/hash preservation, target conflict rejection, staging symlink rejection, and plugin-proof binding. Swift Foundation/POSIX typecheck is performed on the execution subset.

Not claimed: Xcode/iOS SDK build, Darwin compilation, RootHide/Rootless device behavior, real root Helper execution, launchd integration, or actual TweakInject deployment. XCTest source is added but not run in this environment.
