# P2-45-R1 Validation Report

## Baseline
- Input: `FilterKit-P2-44-R18-Source.zip`
- SHA-256: `23296cfd36108584288df00a02094ce4f821d2968869477a167bfc2cf5bd2488`
- ZIP integrity: passed before extraction.
- New worktree: `FilterKit-P2-45-Work/FilterKit-P2-42`; R18 archive/worktree not overwritten.

## Executed checks
- R18 Recovery Boundary Host regression: **80/80 assertions passed**.
- R18 static audit: **16/16 passed**.
- R1 signing/build/write-gate static audit: **10/10 passed**.
- Swift syntax parse: **295/295 files passed** across Sources, App, HelperRuntime, Tests, and Build/scripts.
- Project.yml YAML parse: passed.
- Localizations: English 519/519 unique; Simplified Chinese 519/519 unique; key counts match.
- `plutil -lint`: both Localizable.strings passed.
- Shell syntax: **76/76 scripts passed**.
- Darwin preflight on this Linux host: exited **3 as designed**, explicitly reporting that macOS is required.
- ZIP integrity and SHA-256: performed after packaging.

## Actual blockers / not run
- No macOS host, Xcode, iOS SDK, Apple `codesign`, provisioning profile, or signing identity in this environment. No Apple platform build or signature verification is claimed.
- `Project.yml` currently sets the Helper target `CODE_SIGNING_ALLOWED: NO`; this is a concrete source configuration blocker to a signed Helper release build through that target. It was not silently changed.
- No device, launchd/XPC, RootHide filesystem, installed Helper identity, or ElleKit injection test was available.
- No production write gate was opened. `executionReleased` remains false in all audited production components; provisioning still sets `executionEnabled=false`.

## Result
**P2-45-R1: BLOCKED / NOT RELEASE-QUALIFIED.** R1 supplies a reproducible macOS preflight and establishes the blockers, but it does not qualify a signed production release. Proceed to R2 only with an Apple build host and a defined, verified Helper signing/deployment format. Production write enablement is not authorized by this report.
