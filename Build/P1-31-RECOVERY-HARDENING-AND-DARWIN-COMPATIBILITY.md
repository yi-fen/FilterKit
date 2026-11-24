# P1-31 — Recovery Hardening & Darwin Compatibility Review

## Scope

P1-31 hardens the P1-30 three-file transaction recovery boundary. It does not release deployment, does not change the Helper execution gates, and does not enable automatic startup recovery.

## Recovery integration

- `HelperStartupRecoveryCheck.inspectDetailed` distinguishes clean state, legacy paired-file pending state, P1-30 three-file pending state, both journals pending, and invalid journal state.
- The existing `inspect` API remains as a compatibility adapter for Runtime (`clean`, `recoveryRequired`, `invalidJournal`).
- `HelperAuthorizedRecoveryCoordinator` exposes a separate root-only explicit recovery operation for the P1-30 three-file journal.
- The coordinator refuses to process legacy paired-file journals or mixed-journal state. Those require their own dedicated recovery workflow.
- `FilterKitHelperRuntime` continues to perform read-only inspection and blocks socket service when recovery is pending or invalid. It does not call the mutating coordinator.

## Filesystem validation changes

The three-file transaction now:

- Requires deployed, temporary, backup, and journal files to be root-owned regular files with `root:wheel` ownership.
- Rejects setuid/setgid and group/world-writable transaction files.
- Requires transaction-owned files and journals to have a single hard link.
- Compares `fstatat(..., AT_SYMLINK_NOFOLLOW)` identity with the opened descriptor (`st_dev`, `st_ino`) before hashing.
- Rechecks descriptor identity, owner, group, mode, link count, and size after reading; short reads or concurrent mutation fail closed.
- Opens manifests without following symlinks and validates exact `0600` mode on the opened descriptor.
- Leaves the journal in place when a destination, backup, or temporary file is unsafe or does not match the journal hash.

## Darwin API compatibility review

The implementation uses POSIX interfaces exposed by Darwin and Glibc conditional imports:

- `openat`, `fstatat`, `renameat`, `unlinkat`
- `O_NOFOLLOW`, `O_DIRECTORY`, `O_CLOEXEC`, `AT_SYMLINK_NOFOLLOW`
- `fstat`, `fchown`, `fchmod`, `fsync`, `geteuid`

These interfaces are available in modern Darwin/iOS SDK families, but this project environment has no Xcode, iOS SDK, or Darwin toolchain. Therefore this phase records a source/API compatibility review only; it does **not** claim a Darwin compile, iOS link, code-signing, launchd, or jailbreak-device test.

## Recovery semantics

- Startup inspection is read-only.
- Explicit recovery is root-only and separate from Runtime startup.
- A clean inspection does not mutate files.
- P1-30 journal recovery is idempotent in the Linux isolated smoke test.
- Foreign hashes, symlinks, hard links, unsafe permissions, owner/group mismatch, and incomplete backup state stop recovery and preserve the journal for manual handling.
- No wildcard deletion or arbitrary path is introduced.

## Release gates

All remain closed:

- `HelperProductionDeploymentBackend.executionReleased == false`
- Dispatcher execution release remains false
- Helper deployment manifest template `executionEnabled == false`
- Runtime startup recovery remains read-only
- Plugin deletion remains unavailable
- No real TweakInject write was performed
