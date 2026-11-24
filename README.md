# FilterKit-NEW

FilterKit — RootHide & ElleKit Plugin Manager.

This repository is the clean-start project foundation. It does not modify target app bundles, re-sign apps, or implement an injection engine. ElleKit remains responsible for injection.

## Current foundation

- Bundle ID: `cn.yfen.filterkit`
- Xcode target / scheme: `FilterKit`
- Initial version: `1.0.0` (build `1`)
- Code signing: Automatic for local Xcode; no Team ID or provisioning profile is hardcoded
- Display name: `FilterKit`
- SwiftUI app shell with Home / Apps / Plugins / Settings tabs
- Initial Chinese (Simplified) and English localization resources
- Persisted language preference scaffold
- Settings placeholder for Storage & Cache
- P0-06 domain models, service contracts, environment/profile boundaries, and storage-management contracts
- XcodeGen project specification
- Manual GitHub Actions workflow (`workflow_dispatch`) with environment/profile/configuration/architecture/test/package/clean-build inputs
- Build profile registry and fail-closed profile resolver
- Per-environment isolated build outputs, build report, and SHA-256 manifest
- Local macOS build script

## Build on macOS

Requirements: Xcode with iOS SDK, command line tools, and XcodeGen.

```sh
brew install xcodegen
./Build/Scripts/build.sh
```

Or generate the Xcode project and open it:

```sh
xcodegen generate --spec Project.yml
open FilterKit.xcodeproj
```

## Important status

The deployment target is provisionally set to iOS 15.0 and must be confirmed against the intended jailbreak/device matrix. P0-07 adds manual build inputs and a profile registry. The RootHide entry records the reference ElleKit baseline but still needs device validation. Rootless remains unverified and Auto resolution fails closed. IPA output is unsigned. DEB packaging is deliberately blocked until environment-specific package layout and metadata are verified. Run the workflow manually from the GitHub Actions page.

P0-06 architecture boundaries are documented in `Build/P0-06-ARCHITECTURE.md`. Run `python3 Build/Scripts/verify-architecture.py` for the structural check.

P0-02 identity settings are documented in `Build/PROJECT_IDENTITY.md`. Run `./Build/Scripts/verify-project-config.sh` for static checks. No Xcode build has been executed in this environment; generated-project and signing behavior still require macOS/Xcode verification.

## macOS 本地手动构建（P0-08）

在安装 Xcode、Xcode Command Line Tools 和 XcodeGen 的 Mac 上运行：

```bash
bash Build/Scripts/build-local.sh
```

本地与 GitHub Actions 共用 `Build/Scripts/ci-build.sh`。详细参数、输出目录及当前限制见 `Build/P0-08-LOCAL-BUILD.md`。

## P1-01 Environment Probe

A conservative read-only environment probe is included. It inspects known RootHide/Rootless path candidates and ElleKit file candidates without writing to jailbreak locations. Detection is heuristic; do not treat a detected directory as a verified supported profile. See `Build/P1-01-ENVIRONMENT-PROBE.md`.

## P1-02 — JBROOT validation

P1-02 adds read-only structural validation for JBROOT candidates. Candidate aliases are canonicalized and collapsed, required `usr` and `usr/lib` directories are checked, and multiple distinct valid roots remain unresolved rather than being selected by score. See `Build/P1-02-JBROOT-VALIDATION.md`.

## P1-03 — ElleKit inspection

P1-03 adds read-only inspection of ElleKit-related binary candidates and the
installed `ellekit` dpkg status stanza. Package version and architecture are
reported only from an installed status record; binary presence alone never
produces a version or commit. A version match to the recorded RootHide 1.2-3
reference profile does not verify source commit 16e3e7e. See
`Build/P1-03-ELLEKIT-INSPECTION.md` for evidence levels and limitations.


## P1-02.1 — RootHide / Rootless identification enhancement

P1-02.1 adds dual RootHide container alias scanning, canonical path de-duplication, conservative jbroot name validation, and optional runtime libroot discovery. libroot results are cross-checked against filesystem structure; conflicting roots remain unresolved. JBROOT and rootfs are represented separately. The jbrand checksum and RootHide devkit path translators remain deferred until verified against the target Dopamine implementation and device behavior. See `Build/P1-02.1-ROOT-IDENTIFICATION-ENHANCEMENT.md`.

## Current development stage

P1-18 adds FilterKitBackup import, per-plugin restore review, conflict blocking, and a read-only final confirmation. Actual restore/deployment remains disabled pending the verified Helper and ElleKit strategy stages. See `Build/P1-18-BACKUP-IMPORT-AND-RESTORE-REVIEW.md`.


## Latest engineering phase

P1-30 adds a crash-recoverable three-file transaction for the dylib, Filter.plist, and Root-owned Schema 3 manifest. See `Build/P1-30-ATOMIC-THREE-FILE-TRANSACTION.md` and `Build/TEST-REPORT-P1-30.md`. Production execution gates remain closed pending Darwin and jailbreak-device validation.

### P1-33 trust provisioning

See `Build/P1-33-APP-HELPER-TRUST-PROVISIONING.md` for the mutual App/Helper CDHash trust model, the non-self-referential signing/provisioning sequence, and the remaining device-validation gates.


### P1-34 trusted Helper installer planning

P1-34 adds the post-signing provisioning hand-off, complementary App/Helper CDHash artifact generation, disabled launchd plist rendering, and closed lifecycle transaction/rollback plans. The installer API is validation-only; no root installation, launchd operation, or deployment execution is performed. See `Build/P1-34-TRUSTED-HELPER-INSTALLER-AND-LIFECYCLE.md` and `Build/TEST-REPORT-P1-34.md`.

### P1-35 trusted Root Installer transaction framework

P1-35 adds exact staged-artifact SHA-256 verification, fixed disabled launchd plist validation, a replayable hash-chained installer transaction journal, and an explicit execution gate. The journal is not yet persisted and no production Root Installer adapter exists; all install plans remain blocked. See `Build/P1-35-TRUSTED-ROOT-INSTALLER-TRANSACTION-FRAMEWORK.md` and `Build/TEST-REPORT-P1-35.md`.

### P1-36 durable Root journal and recovery assessment

P1-36 adds a root-owned 0700 directory journal store with no-follow path traversal, bounded reads, 0600 journal files, file/directory fsync and atomic rename. It also adds read-only crash-recovery recommendations after full journal-chain validation. No privileged Root Installer or activation adapter exists; deployment remains disabled. See `Build/P1-36-DURABLE-ROOT-JOURNAL-AND-RECOVERY.md` and `Build/TEST-REPORT-P1-36.md`.

### P1-37 Root release-set verification and recovery preflight

P1-37 defines and verifies the exact three-artifact Root Helper release set (Helper executable, disabled Root deployment manifest, disabled launchd plist), and adds read-only recovery decisions based on observed hashes and ownership evidence. This is not yet a filesystem activation executor; no privileged install, rollback, or launchd operation is available. All execution gates remain closed. See `Build/P1-37-ROOT-RELEASE-ACTIVATION-PREFLIGHT.md` and `Build/TEST-REPORT-P1-37.md`.


### P1-38 Root Helper multi-directory activation transaction

P1-38 adds a standalone, root-only activation executor for the Helper executable, Root deployment manifest, and launchd plist across their three destination directories. It revalidates the exact disabled release set, uses no-follow directory traversal, stages and fsyncs files, preserves previous versions, journals each activation step, and supports hash-checked rollback or manual-intervention fallback after interruption. The executor is not connected to HelperRuntime; `executionEnabled=false` remains unchanged. See `Build/P1-38-ROOT-ATOMIC-ACTIVATION.md` and `Build/TEST-REPORT-P1-38.md`.

### P1-39 Darwin filesystem hardening and fault injection

P1-39 adds a persistent root-owned `flock` transaction lock shared by activation and recovery, rejects unsafe lock/artifact/journal inode metadata, avoids FIFO blocking and `/dev/fd` journal reopening, and adds deterministic transaction fault points. The executor remains standalone and `executionEnabled=false` is unchanged. Host validation is Linux-only; Darwin runtime behavior and RootHide device operation remain unverified. See `Build/P1-39-DARWIN-HARDENING-AND-FAULT-INJECTION.md` and `Build/TEST-REPORT-P1-39.md`.


## P1-40 — Code Signature Identity & Startup Preflight

P1-40 adds installer-pinned running Helper CDHash verification, a macOS Security.framework static-code verification path for release tooling, and an explicit read-only HelperRuntime startup preflight that inspects transaction journals before the IPC listener is created. Pending/invalid recovery state is reported without mutation; execution remains disabled. See `Build/P1-40-CODE-SIGNATURE-AND-STARTUP-PREFLIGHT.md` and `Build/TEST-REPORT-P1-40.md`.

## P1-41 — Release Trust & Helper Identity Provisioning

P1-41 adds a versioned `HelperReleaseTrustManifest`, release-to-provisioning binding, Helper SHA-256/CDHash verification, and optional Team ID plus leaf-certificate fingerprint pins. A macOS-only script extracts identity from the final signed Helper. The release-aware startup preflight remains read-only; platform-specific runtime acquisition and cryptographic signing of the trust manifest are not yet implemented. See `Build/P1-41-RELEASE-TRUST-AND-IDENTITY-PROVISIONING.md` and `Build/TEST-REPORT-P1-41.md`.


## P1-42 — Signed Release Manifest & Anti-Rollback Protection

P1-42 adds an Ed25519 signed release envelope, canonical payload encoding, trusted signing-key allowlist with revocation states, a Keychain-backed device-local highest-generation record, a macOS release-side signing utility, and a signed-release HelperRuntime preflight path. A signed-release preflight API is available, but the live `FilterKitHelperRuntime.run()` call site is not yet switched because a production release keyring and signed provisioning artifacts have not been provisioned; the current startup path still uses the legacy CDHash-only check. Keychain state is not a hardware monotonic counter and cannot defeat a privileged attacker or full device-state rollback. Real CryptoKit/Keychain and RootHide validation remain outstanding. See `Build/P1-42-SIGNED-RELEASE-AND-ANTI-ROLLBACK.md` and `Build/TEST-REPORT-P1-42.md`.

### P1-43 release trust runtime

The Helper's production startup now requires a signed Ed25519 release envelope and persistent anti-rollback state. The checked-in `HelperReleaseTrustAnchors.swift` is intentionally empty; provision reviewed public keys for a release build with `Build/Scripts/configure-helper-release-keys.py`. Until then, Helper startup fails closed. See `Build/P1-43-SIGNED-TRUST-RUNTIME-INTEGRATION.md` and `Build/TEST-REPORT-P1-43.md`.


### P1-44 Apple platform verification

P1-44 adds CryptoKit Ed25519 known-answer tests, Keychain anti-rollback persistence/concurrency tests, an append-only Keychain generation ledger, and Apple test/provisioning audit scripts. Run `FILTERKIT_TEST_DESTINATION='platform=iOS Simulator,id=<UDID>' Build/Scripts/run-apple-platform-tests.sh` on macOS with XcodeGen/Xcode. The checked-in trust-anchor list remains empty until a reviewed production keyring is supplied; see `Build/P1-44-APPLE-PLATFORM-VERIFICATION.md`.
