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

## P2-26 — Darwin Recovery Authorization Integration

P2-26 corrects the maintenance authorization peer model for the App-to-root-Helper architecture. The FilterKit App remains an unprivileged peer; the Helper process performs privileged operations. Reconciliation requests now require an explicit UI confirmation intent, a Transaction ID, a request nonce equal to the IPC envelope request ID, fresh authenticated session evidence, and complete Darwin Audit Token/PID Generation evidence. The Helper mints a short-lived transaction-scoped capability only after the existing peer trust policy has authenticated the App identity.

Actual recovery mutation remains disabled pending Apple SDK and RootHide device validation. The `operatorConfirmed` field is a UI intent signal, not cryptographic proof of human presence. See `Build/P2-26-DARWIN-RECOVERY-AUTHORIZATION-INTEGRATION.md` for the security boundary and validation limits.

## P2-27 — Darwin App Identity Provisioning & Maintenance Channel Validation

P2-27 adds explicit root Helper UID/GID expectations to newly generated App trust configuration, checks the running App's own kernel-reported CDHash availability before connecting, and wires the App-side peer trust evaluator to provisioned Helper identity constraints. A cross-check policy binds the installer provisioning record, embedded App trust generation and Helper CDHash, final App/Helper CDHashes, measured client UID/GID, and root Helper UID/GID. `Build/scripts/p227_identity_provisioning_audit.py` provides a read-only macOS audit for final signed artifacts; target UID/GID must be measured on the RootHide device and supplied explicitly. This does not perform installation or runtime IPC. See `Build/P2-27-DARWIN-APP-IDENTITY-PROVISIONING.md`.

## Latest development phase

- **P2-28 — Plugin Toggle Release Gate**: adds a fail-closed readiness policy for staged per-App enable/disable and injection rollout. Real mutation remains locked pending signed artifact and RootHide device validation. See `Build/P2-28-PLUGIN-TOGGLE-RELEASE-GATE.md`.

## P2-32 App Detail Plugin Management

The Apps tab now opens an App detail page with a visible **Import Plugin** action and an app-scoped list of related plugins. Import currently provides file selection and read-only review only; real installation, association commits, enable/disable, and uninstall remain behind the production safety gates. See `Build/P2-32-APP-DETAIL-PLUGIN-MANAGEMENT.md`.

## P2-33 — Plugin Identity & Filter Diagnostics

P2-33 adds bounded read-only Mach-O and plist inspection to the plugin inventory. Plugin details expose architecture, UUID, CDHash, CodeDirectory identifier/Team ID/flags/platform, SHA-256, and the parsed Bundles/Executables/Classes/Mode fields. Settings shows the scanned Filter inventory, ElleKit compatibility-profile state, and FilterKit's own executable identity. These are diagnostic signals only: they do not prove code-signature validity, package ownership, or successful injection. All production mutation gates remain closed. See `Build/P2-33-PLUGIN-IDENTITY-AND-FILTER-DIAGNOSTICS.md`.

## P2-34 — Home / App / Plugin Product Architecture

P2-34 formalizes the four-page responsibility boundary: Home is the device overview, App detail is the sole first-time dylib/plist import and per-App activation entry point, Plugins is the plugin library plus soft-association and backup-data management, and Settings contains low-level environment/security diagnostics. See `Build/P2-34-VALIDATION-REPORT.md`.

## P2-35 — Plugin Soft Association Manager

P2-35 adds a soft-association checklist to FilterKit-managed plugin detail pages. The hard-bound App is displayed as immutable and excluded from selectable Apps. Third-party, unknown, unpaired, identity-conflicted, and otherwise unauthorized plugins remain read-only. Association changes are an in-memory draft with an explicit change preview; no manifest or Filter.plist is written in this phase. Newly created soft associations default to inactive, and re-adding a relationship within the same draft preserves its original activation bit. The Plugins page has no enable/disable controls; activation remains an App-detail responsibility. See `Build/P2-35-SOFT-ASSOCIATION-MANAGER.md` and `Build/P2-35-CHANGELOG.md`.
\n\n## P2-36\n\nP2-36 adds Helper-side soft-association mutation policy and host audit. Production persistence remains release-gated pending signed-artifact and RootHide device validation; see `Build/P2-36-VALIDATION-REPORT.md`.\n
### P2-36-R1
See `Build/P2-36-R1-CHANGELOG.md` and `Build/P2-36-R1-VALIDATION-REPORT.md`. The complete soft-association replacement intent and Plugin detail Save confirmation are restored, while both real-write release gates remain closed.

### P2-37 — APP Detail Plugin Activation Manager

P2-37 adds hard-bound / soft-associated plugin grouping in App Detail, per-target activation observations, manifest-versus-`Filter.Bundles` cross-checks, and independent local switch previews. Hard-bound associations remain immutable but their activation state is not inherently locked. Third-party, unknown, unverified, ambiguous, and inconsistent plugin states remain non-actionable. The switches are preview-only and do not write configuration, contact Helper for mutation, or enable injection. Current inventory intentionally fails closed because its scanner has not yet supplied trusted ownership and binary-identity verification. See `Build/P2-37-CHANGELOG.md` and `Build/P2-37-VALIDATION-REPORT.md`.

## P2-37-R2 — Helper Plugin Identity Attestation

P2-37-R2 adds a read-only Helper IPC endpoint that independently verifies a FilterKit plugin's root-owned schema-3 manifest, package-manager ownership status, dylib/plist SHA-256 values, Mach-O identity fingerprint, and parsed Filter projection. The APP detail activation preview now requires a fresh Helper-authored attestation that matches the local inventory snapshot. This phase does not execute enable/disable mutations; all production release gates remain closed.

Validation details: `Build/P2-37-R2-VALIDATION-REPORT.md`.

## Current development stage: P2-37-R3

P2-37-R3 tightens App-detail activation preflight and state consistency. It binds Helper identity evidence to the exact manifest/dylib/plist scan, expires evidence after 120 seconds, invalidates it when file metadata changes, cross-checks the complete soft-association set against `Filter.Bundles`, and keeps App controls preview-only. See:

- `Build/P2-37-R3-CHANGELOG.md`
- `Build/P2-37-R3-VALIDATION-REPORT.md`
- `Build/P2-37-R3-ACCEPTANCE-CHECKLIST.md`

Apple SDK compilation, XCTest on Apple platforms, signed Helper IPC, and RootHide/ElleKit device acceptance remain pending. Production mutation gates remain closed.

## Current development stage: P2-37-R4

P2-37-R4 defines the APP single-target activation command, Helper authorization plan, and post-commit state proof. Commands bind one plugin + one Bundle ID + desired/expected activation state + current Filter.plist and Manifest hashes. Helper plans and proofs must echo the exact target and hash preconditions. The new protocol is currently a model/contract layer only: it is not yet wired into IPC dispatch or the APP switch, and no production write path is enabled. See `Build/P2-37-R4-CHANGELOG.md` and `Build/P2-37-R4-VALIDATION-REPORT.md`. Production gates remain closed.

## Current development stage: P2-37-R5

P2-37-R5 wires the R4 single-App activation command into dedicated authenticated Helper IPC prepare/commit routes. Both routes use the existing session, freshness, replay, recovery, and audit controls. Helper independently checks the actual prior activation state against the command. Prepare is read-only; commit reauthorizes but is explicitly rejected while the production write gate is closed. See `Build/P2-37-R5-CHANGELOG.md` and `Build/P2-37-R5-VALIDATION-REPORT.md`.

## Current development stage: P2-37-R6

P2-37-R6 binds Commit to the exact Helper-authored Prepare plan, uses a fresh transport request ID so the replay guard does not mistake Commit for a replay of Prepare, reauthorizes ownership and current file hashes at the commit boundary, and wires the existing Filter.plist + `.fk.json` Journal transaction into the activation route. A commit proof is derived only from the transaction receipt; no-op requests carry no transaction ID. The production activation commit gate remains closed, and the production Helper does not enable the test-only execution switch. See `Build/P2-37-R6-CHANGELOG.md`, `Build/P2-37-R6-VALIDATION-REPORT.md`, and `Build/P2-37-R6-ACCEPTANCE-CHECKLIST.md`.

## Current development stage: P2-37-R7

APP Detail now orchestrates Helper Prepare, explicit confirmation, fail-closed Commit coordination, proof validation, and authoritative read-only scan refresh. The APP and Helper production Commit gates remain closed pending Apple-platform and RootHide/ElleKit device acceptance. See `Build/P2-37-R7-VALIDATION-REPORT.md`.

## P2-39-R3 Runtime Diagnostics

P2-39-R3 adds a Settings → Runtime Diagnostics screen and bounded local log persistence for the existing App Discovery and Plugin Inventory performance summaries. Logs are stored under the app sandbox's `Library/Application Support/FilterKit/Logs/`, rotated at approximately 1 MiB with one previous file retained, and can be exported or cleared from Settings. The diagnostics path is observational only and does not initiate scans or alter the Helper/Release Gate policies. See `Build/DeviceAcceptance/P2-39-R3-RUNTIME-DIAGNOSTICS.md` for device acceptance steps.


## Runtime event records (P2-39-R4 foundation)

FilterKit writes local-only structured JSON Lines records under the app container:

`Library/Application Support/FilterKit/Logs/`

- `runtime.jsonl`: developer-oriented runtime events, using OpenTelemetry-style timestamp, severity, resource, instrumentation-scope, event, trace/session, and attributes fields.
- `runtime.previous.jsonl`: the previous bounded developer log segment.
- `activity.jsonl`: user-facing events projected from the same event source; Settings > Activity History displays only these user-facing records.

Developer runtime logs are not displayed in the FilterKit UI. They can be inspected through the app data container (for example, Filza). Logging is asynchronous, bounded, local-only, and must never initiate inventory scans or mutate plugin state.

The current source instruments app launch/scene lifecycle and completed/failed plugin inventory scans. `RuntimeEventLogger.recordPluginOperation` is the required integration point for future import, activation, association, and uninstall implementations. Those operations must call it only after the real operation result is known. This source snapshot does not contain active end-to-end plugin import/uninstall flows, so it intentionally does not fabricate those history entries.

An unconfirmed prior-session marker is reported as a *suspected/unconfirmed abnormal termination*, not a confirmed crash. iOS does not guarantee an app termination callback, and this app cannot assume it can read system `.ips` crash reports from its sandbox.
