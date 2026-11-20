# Stage 2.4 R4-D2 — RootHide DEB Build Pipeline Optimization

- Status: implementation in the uploaded source snapshot; local static/package fixture checks only.
- Authorization: user explicitly authorized 0.1-D-R4-D2 optimization, code changes and macOS Runner workflow integration.
- Scope: RootHide-default DEB package profile, package script, static validator, workflow wiring and documentation.
- Explicitly not included: R4-G device install/launch, device signing or entitlement release, RootHide `jbroot()` calls, plugin/config writes, 0.1-E final release acceptance.

## 1. Profile semantics

The default DEB profile is `roothide-rootfs`:

- package payload path: `Applications/FilterKit.app` (rootfs-relative; no `var/jb/` prefix);
- dpkg `Architecture`: `iphoneos-arm64e`, retained as the package-manager label from the archived same-device package comparison;
- minimum Mach-O device slice: `arm64`, checked independently;
- payload ownership: root:root, mandatory `dpkg-deb --root-owner-group`;
- `postinst`: reviewed registration-only script, unchanged in behavior.

The dpkg Architecture field is not treated as a Mach-O slice declaration. This removes the invalid assumption that the app binary must be forced to arm64e merely because the package metadata says iphoneos-arm64e.

The profile does **not** claim RootHide-native linkage. No `libroothide`, weak-link flag, or rpath was invented or added because the current Xcode project snapshot contains no verified RootHide SDK/header/library integration and the app's current source does not establish a concrete `jbroot()` link requirement.

## 2. Code changes

- Added `Config/DEB/roothide.env` as the single profile metadata source.
- Reworked `scripts/package-deb.sh`:
  - defaults to `roothide-rootfs`;
  - verifies `Info.plist`, `CFBundleExecutable`, executable bit and control package architecture;
  - requires `dpkg-deb --root-owner-group` and fails closed if unavailable;
  - prefers macOS `ditto` for App Bundle staging (resource forks/extended attributes/symlinks) and uses `cp -R` only as a portable fallback;
  - deletes stale output before input validation and verifies the generated archive immediately;
  - derives default artifact filename from the control Version.
- Added `scripts/compare-app-bundles.py`:
  - compares Info.plist, all bundle entries, file SHA256, symlink targets and executable bits;
  - does not follow symlinks while inventorying.
- Reworked `scripts/validate-deb.sh` with checks e1-e9:
  - archive extraction;
  - control/profile/Bundle ID/version consistency;
  - reviewed postinst byte identity and shell syntax;
  - RootHide rootfs-relative path and no `var/jb/` leak;
  - root:root ownership (GNU tar and bsdtar listing formats);
  - declared executable presence and executable bit;
  - complete source-vs-packaged bundle parity;
  - Mach-O `arm64` slice independent from dpkg Architecture;
  - signature state reported without treating unsigned as installable.
- macOS Runner workflow:
  - explicit `ARCHS=arm64 ONLY_ACTIVE_ARCH=NO` for the generic iOS device build;
  - replaces GNU-only `find -maxdepth` usage with BSD/macOS-compatible `find -print -quit`;
  - selects `roothide-rootfs` for the default DEB job;
  - validates the package against the exact source `.app` tree;
  - requires validation tools in CI so missing architecture/parity/ownership checks fail instead of silently passing;
  - uploads the version-derived DEB artifact and machine-readable summary.
- Aligned DEB Version to current `project.yml` `MARKETING_VERSION=0.0.1`: `0.0.1-1`; the package script and validator reject Bundle ID or marketing-version drift.

## 3. Local verification performed

A synthetic `.app` fixture was packaged with the local Linux `dpkg-deb` 1.22.22 and validated:

- package creation succeeded;
- `dpkg-deb --info` and extraction succeeded;
- e1-e7 passed, including root:root ownership and full source/payload parity;
- e8 Mach-O architecture was unavailable because this Linux environment has no Apple `lipo` and the fixture is not a real Mach-O;
- e9 signature inspection was unavailable because Linux has no Apple `codesign`;
- JSON summary parsed successfully.

This fixture test does not replace the macOS Runner execution on a real `Release-iphoneos` app.

## 4. Pending evidence

- macOS Runner must execute the updated workflow on the actual repository commit.
- Runner must confirm the generated app is iPhoneOS arm64, not Simulator.
- Runner must pass e1-e8 with actual app content and archive ownership.
- Runner signature result will likely be `unsigned` for the current `CODE_SIGNING_ALLOWED=NO` path; this is expected and must remain labeled non-installable.
- RootHide linkage/rpath requirements remain unknown until target SDK/header/library evidence is available.
- R4-G install, registration, launch and crash-log diagnosis remain pending and are not covered by this implementation record.
