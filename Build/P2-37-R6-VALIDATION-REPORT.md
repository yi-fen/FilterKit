# P2-37-R6 Validation Report

## Baseline

- Input: `FilterKit-P2-37-R5-Activation-IPC.zip`
- SHA-256: `33a792e4701d051a42837ce5dd71c270a7f6ef0e3acc18aef1fdb9edfcf6ed7b`
- ZIP integrity: passed before extraction.

## Validation

- P2-37-R6 transaction integration static audit: 22/22 checks.
- P2-37-R5 IPC regression audit updated for the R6 Commit executor: 21/21 checks.
- P2-36-R2 transaction audit updated to assert each route has its own gate: 17/17 checks.
- Helper source-set semantic typecheck using host Swift SDK: passed with the complete required model source set.
- Existing dual-file transaction Host Smoke: all journal phases, successful commit, foreign-modification rejection, SIGKILL recovery and IPC compatibility passed.
- Swift frontend parse: all `Sources`, `App`, and `Tests` files.
- Existing P2-36-R2 transaction audit and Host Smoke.
- Existing P2-37-R5 IPC audit and all R1–R4/R2 transaction and IPC regression audits.
- Project YAML parse and shell syntax checks.
- Archive integrity after packaging.

Swift frontend parse is syntax validation only. It is not an Xcode/iOS SDK semantic build. XCTest sources are not executed by Apple's XCTest Runner in this Linux environment.

## Not executed

- XcodeGen / Xcode iOS build.
- Apple XCTest Runner.
- Live signed Darwin App-to-Helper IPC.
- RootHide / ElleKit device validation.
- Real filesystem commit on a jailbreak device.
- Device-level Helper termination during each journal phase and restart/recovery.

## Release state

`pluginAssociationCommitReleased == false`; production Helper construction leaves the test-only `activationCommitExecutionEnabled` default false. Production commit remains fail-closed with `execution_disabled`.

## Runner caveat

The legacy aggregate wrapper `Build/Host/run-p236r2-phase2-host-smoke.sh` was attempted but did not complete: its all-files Swift frontend invocation includes multiple legacy Host Smoke files with top-level executable expressions, which Swift 6.2 rejects when compiled in that aggregate invocation. The equivalent P2-36-R2 transaction smoke executable was then compiled and run separately with the required Helper/model source set; all 6 Journal phases, successful two-file commit, foreign-modification rejection, SIGKILL recovery, IPC compatibility, and closed release gates passed. This is a runner composition issue; it is not represented as an R6 XCTest pass.
