# P1-21 — Helper Runtime, Manifest Trust, Audit Persistence & Lifecycle

## 1. Input and verified P1-20 state

Built from `FilterKit-NEW-P1-20.zip`. P1-20 contains a reusable AF_UNIX client/server, nonce handshake, Darwin peer credential/CDHash provider, replay guard, audit record protocol, and lifecycle profile. Its own test report explicitly states there was no Helper executable target, no launchd plist, no root manifest reader/installer, and no persistent audit writer. `executionReleased` remained false.

## 2. P1-21 implementation

### 2.1 Separate Helper executable target

- Added `FilterKitHelper` command-line-tool target to `Project.yml`, separate from the iOS App target.
- Added `HelperRuntime/main.swift` as the independent process entry point.
- The runtime target compiles only the helper runtime, IPC models/transport, libroot path probe, and supporting path evidence types.
- No App UI or App lifecycle is linked into the Helper target.

XcodeGen/Xcode build was not available in this environment; target generation and iOS link compatibility remain to be verified on macOS/Xcode.

### 2.2 Root-owned manifest reader

`HelperSecureManifestStore` reads the manifest using component-by-component `openat` with `O_DIRECTORY | O_NOFOLLOW`, then opens the leaf with `O_NOFOLLOW`. It requires:

- regular file;
- uid 0;
- exact mode 0600;
- size <= 64 KiB;
- supported schema;
- clean absolute paths;
- valid 40-character CDHash entries;
- non-empty allowed UID list.

It is read-only. No App-facing manifest write API exists.

### 2.3 Runtime startup gate

`FilterKitHelperRuntime`:

1. resolves jbroot through the existing libroot runtime probe;
2. fails closed if jbroot cannot be resolved;
3. reads `<jbroot>/Library/FilterKit/Helper/manifest.json`;
4. requires manifest jbRoot to match the runtime-resolved jbroot;
5. requires TweakInject and socket paths to remain under that jbroot;
6. obtains Helper CDHash through the Darwin csops provider;
7. verifies its own CDHash against the root-owned manifest;
8. starts the existing AF_UNIX server with UID/App-CDHash trust policy.

No `/var/jb` guess is used as a fallback. RootHide and Rootless both depend on a validated libroot result; this behavior remains device-unverified.

### 2.4 Health-only runtime

The runtime accepts `healthRequest` and returns `healthResponse`. Every `operationRequest` is audited and rejected with `execution_not_implemented` regardless of `manifest.executionEnabled`.

This is deliberate: P1-21 creates a separately launchable runtime shell but does not link a root file executor. There is no path in this build that can copy, replace, or delete files in TweakInject.

### 2.5 Persistent audit writer

`HelperAuditFileSink` writes bounded JSONL records and:

- uses fd-relative `openat` with `O_NOFOLLOW`;
- requires a root-owned, non-group/world-writable parent directory;
- requires the log to be a regular root-owned file with mode 0600;
- records structured metadata only, never dylib/plist bytes;
- rotates bounded log generations.

The sink is invoked for health and rejected operation requests. Full crash-safe fsync policy and device filesystem behavior remain for on-device validation.

### 2.6 Lifecycle plans and launchd template

Added `HelperLifecyclePlan` for fixed install/start/stop/uninstall/re-pin artifact paths and owner/mode expectations. Every plan requires a root installer and cannot run from the App.

Added a launchd plist template with `Disabled=true`, `RunAtLoad=false`, and `KeepAlive=false`. This is intentionally not an active service definition. The conservative persistent profile (RunAtLoad/KeepAlive) remains a future post-validation choice.

`Build/Helper/INSTALLATION-AND-REPINS.md` defines:
- fixed executable/plist/manifest/audit/socket layout;
- install/start/stop/uninstall ownership;
- socket cleanup only after exact label shutdown and socket inode/type/owner validation;
- re-pin only through a trusted root installer after recomputing both App and Helper hashes.

No generic launchctl script was added because RootHide/Rootless bootstrap entry points and package lifecycle hooks are not verified on device.

## 3. Security decisions

- App cannot install, start, stop, uninstall, or re-pin Helper.
- Manifest is root-owned and read-only to Helper runtime.
- Helper startup fails closed on missing libroot, unsafe manifest, root mismatch, invalid paths, or CDHash mismatch.
- AF_UNIX reachability is not trust; UID/PID/CDHash checks remain mandatory.
- P1-20's PID + csops race remains open; audit token/pidversion is not implemented.
- Runtime is health-only; all privileged file operations remain disabled.
- `removeUnmanagedDylib` remains unavailable pending FilterKit ownership proof.

## 4. Validation

Planned checks:
- full Swift parse;
- Helper runtime subset Foundation typecheck on Linux;
- secure manifest reader tests for path traversal/symlink/mode/owner/size;
- lifecycle plan fixed paths and root-installer-only policy;
- audit JSONL append/rotation smoke using a temporary root-owned directory;
- ZIP integrity.

Not claimed: XcodeGen generation, Xcode/iOS SDK build, Darwin csops execution, launchd bootstrap, root Helper installation, RootHide/Rootless device validation, or actual TweakInject writes.
