# P0-07 — GitHub Actions manual build

## Inputs
- Environment: RootHide / Rootless / Both (Both creates isolated matrix jobs).
- Profile: Auto or the registered RootHide reference profile. A profile/environment mismatch is rejected.
- Configuration: Debug / Release.
- Architecture: arm64e / arm64 / Both. `Both` requests separate architecture slices in one Xcode build setting; actual support depends on the selected Xcode SDK/toolchain.
- Tests: Yes / No.
- Package: DEB / IPA / Both / None. IPA is an unsigned Payload archive. DEB packaging is enabled for the registered RootHide profile and installs the app bundle at /Applications/FilterKit.app. Rootless DEB packaging remains blocked until its package layout is verified.
- Clean Build: Yes / No.

## Profile safety
`Build/Profiles/profiles.json` is the registry. The RootHide entry records the project reference baseline ElleKit 1.2-3 / commit 16e3e7e; it is not a claim of device-level validation. Rootless is listed as unverified and has no selectable formal profile. Auto resolution fails closed when no unique registered profile exists.

## Artifacts
Each environment writes `FilterKit.app`, optional unsigned IPA, `xcodebuild.log`, `profile.json`, `build-report.json`, and SHA256SUMS.txt. The report records selected inputs, toolchain, commit, timestamp, and artifact hashes.

## Current limitations
- Workflow is manual (`workflow_dispatch`) only.
- No real GitHub Actions run has been performed by this local source-generation step.
- No macOS/Xcode build has been run here.
- Rootless profile is not verified.
- DEB packaging is guarded and exits with an explicit explanation rather than producing a misleading package.
- arm64e support depends on Xcode/SDK acceptance; the workflow exposes the requested option but does not claim all Apple toolchains support it.

A small XCTest target is included for the hard-bound/soft-association model invariant. The workflow's Tests input runs this test target when enabled.
