# P2-39-R2 — Runtime Acceptance Preparation

## Scope delivered in this environment

- Reopened and inspected the P2-39-R1 Scan Reduction source archive.
- Re-ran the R1 static scan-reduction acceptance audit: **18/18**.
- Re-ran Swift syntax parsing over `Sources`, `App`, `HelperRuntime`, and `Tests/UnitTests`.
- Added an Apple build/device XCTest preflight runner.
- Added a RootHide/ElleKit device runtime acceptance protocol with explicit counters, scenario steps, pass criteria, and result recording.

## Not executed

This environment is Linux (`x86_64-unknown-linux-gnu`) and does not provide `xcodebuild`, `xcodegen`, `xcrun`, a connected iPhone, or a RootHide/ElleKit runtime. Therefore no Apple SDK build, XCTest run, on-device scan timing, real file I/O measurement, or Helper IPC timing is claimed.

## Source changes

No production scanning, caching, association, attestation, activation, or injection behavior was changed in R2. This is deliberate: R2 is an acceptance stage, and runtime behavior must be measured before making further optimization changes.

## Required next evidence

Run `Build/Host/run-p239r2-runtime-preflight.sh` on macOS with XcodeGen/Xcode and `FILTERKIT_DEVICE_UDID` set. Then complete the manual scenarios in `Build/DeviceAcceptance/P2-39-R2-RUNTIME-ACCEPTANCE.md` on a dedicated RootHide + ElleKit device. Until then R2 remains **Prepared / Device Acceptance Pending**, not Passed.
