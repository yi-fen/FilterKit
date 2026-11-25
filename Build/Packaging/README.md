# FilterKit Debian packaging (P1-47.2)

## Current supported output

The DEB packaging pipeline is enabled for the registered **RootHide** profile.
Rootless remains explicitly unverified and is rejected by the packaging script.

The package is named `cn.yfen.filterkit` and contains the app at:

`/Applications/FilterKit.app`

The Debian architecture is `iphoneos-arm64`. This is intentional: the
installable iOS application executable is built as **arm64**, including when
the workflow's device label is `arm64e`. An arm64 iOS app runs on arm64e devices;
this project does not ship an arm64e-only app executable. The build report
records both the requested device label and actual app-binary architecture.

## Code signing

The Xcode CI build remains `CODE_SIGNING_ALLOWED=NO` so it does not depend on an
Apple Developer account, certificate, or provisioning profile. Before DEB
creation, the package script signs the copied app bundle with an **ad-hoc code
signature** using Apple's `codesign`, recursively signs nested code, and
verifies the signature. It also checks that the main executable contains an
arm64 Mach-O slice. This avoids shipping an unsigned app bundle, which can
cause SpringBoard launch failure or an immediate crash after installation.

Ad-hoc signing is not an Apple Developer distribution signature and does not
grant private/platform entitlements. The project currently declares no app
entitlements file. If a future feature requires privileged entitlements, those
must be handled through the supported jailbreak installation/signing model;
they must not be guessed or silently added here.

## Installation registration

The package includes a best-effort `postinst` that calls `uicache -p` for
`/Applications/FilterKit.app` when `uicache` is available. A cache-refresh
failure is deliberately non-fatal and cannot cause dpkg to report the entire
installation as failed.

## Build requirements

Run on macOS with Xcode, XcodeGen, Python 3, `dpkg-deb`, `codesign`, and `lipo`.
The GitHub Actions workflow installs `dpkg` with Homebrew when `PACKAGE=DEB`
or `Both`; Apple's signing and Mach-O tools come from the macOS runner.

The CI sequence is:

1. Resolve the selected RootHide profile.
2. Build the iOS app executable as arm64 (not arm64e-only).
3. Copy the app into the DEB staging tree.
4. Apply and verify an ad-hoc code signature to the staged app.
5. Generate Debian control metadata and a best-effort SpringBoard registration script.
6. Build and inspect the DEB payload and control archive.

The DEB does not require an Apple Developer certificate. An IPA, if requested,
remains a separate unsigned artifact and is not made installable by this DEB
signing step.

## Deliberate safety boundary

This package contains only `FilterKit.app`; it does not install or activate the
privileged Helper or launch daemon. It does not claim to solve privileged
plugin-directory or DPKG access. Rootless packaging remains blocked until its
payload prefix and package-manager behavior are verified on-device.
