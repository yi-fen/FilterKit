# P2-43-R5 Validation Report

## Baseline

- Input: `FilterKit-P2-43-R4-Source.zip`
- Expected SHA-256: `b22c63f1bcecb9e828157985b09a7554d510c4055c4074659102b64a8416fcac`
- Baseline archive integrity: `unzip -t` passed.
- Worktree: fresh `FilterKit-P2-43-R5-Work/FilterKit-P2-42`; R4 archive and worktree were not modified.

## Security design outcome

R5 adds a signed client identity tuple to the Helper trust boundary:

`kernel socket audit token -> SecTask -> signing identifier + Team ID entitlement`

The root-owned manifest pins the expected Bundle ID and Team ID; the exact App CDHash remains a separate pin. Missing signed identity evidence rejects authentication. A Bundle ID in an IPC payload cannot override these values.

## Commands and test results

- `swiftc --version`: Swift 6.2.1, `x86_64-unknown-linux-gnu`.
- `swiftc -frontend -parse` over all `Sources/**/*.swift` and `Tests/**/*.swift`: initial R5 pass 246/246; final rerun result recorded before packaging.
- `Build/Host/run_p243_r5_identity_smoke.sh`: 4/4 assertions passed.
- `Build/scripts/p243_r5_code_identity_binding_audit.py`: 13/13 assertions passed.
- Retained prior audits: R4 11/11, R3 14/14, R2 14/14, R1 12/12, R24 12/12.
- `Project.yml` YAML parse passed.
- `Resources/en.lproj/Localizable.strings` and `Resources/zh-Hans.lproj/Localizable.strings`: 519 unique keys each, key sets identical.
- Project YAML parse, localization parity, and retained prior-phase audit scripts: final results recorded before packaging.

## Not validated

- `xcodebuild` and `xcodegen` are not installed in this Linux environment; no Xcode/iOS SDK build was possible. The Darwin-only `Security` API branch has not been typechecked against the project's target SDK.
- No XCTest execution, actual `AF_UNIX` peer-token test, Security `SecTask` integration test, app-upgrade/reinstall test, code-signing/Team ID verification against a signed artifact, or RootHide/ElleKit device test was run.
- The Apple Security API use is implemented in source but must not be described as production-verified until the Darwin build and device tests pass.

## Release posture

All production write gates remain closed. The new startup validator rejects manifests missing Bundle ID or Team ID. No production injection, activation, association, restore, or uninstall capability is released by R5.
