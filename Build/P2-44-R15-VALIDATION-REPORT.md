# P2-44-R15 Validation Report

## R15 results

- Real Store Write Integration Host Smoke: **16/16 assertions passed**.
- R15 static integration audit: **26/26 passed**.
- R14 real Store Host Smoke regression: **10/10 passed**.
- R14 real Store static audit regression: **24/24 passed**.
- R13 Prepared Activation Host regression: **10/10 passed**.
- R1–R14 available historical static audits executed by `run_p244_r15_validation.sh`: all passed. The script output records the individual audit totals.

## R15 Host assertions

1. Production Coordinator `prepare()` creates a Prepared Upgrade.
2. Previous Store preserves actual Active bytes against the supplied trusted old inventory.
3. Previous Store advances the durable Journal.
4. Staged Store writes the verified release bytes.
5. Staged Store advances the durable Journal to `staged`.
6. Staged artifacts can be reopened and hash-verified.
7. Previous backup artifacts can be reopened and hash-verified.
8. Previous preservation leaves Active files unchanged.
9. Staged inspection reports a complete transaction.
10. Injected Previous preservation interruption is surfaced.
11. Interrupted Previous backup remains partial evidence.
12. Interrupted Previous backup retains pending Journal intent.
13. Injected Stage interruption is surfaced.
14. Interrupted Stage remains partial and is not promoted.
15. Interrupted Stage retains pending Journal intent.
16. Host process runs as root for root-owned Store checks.

## Project checks

- Swift syntax parse: **274/274** files passed (`Sources` + `Tests`).
- `Project.yml` YAML parse: passed.
- English localization: 519 unique keys, no duplicates.
- Simplified Chinese localization: 519 unique keys, no duplicates.
- English/Chinese localization key parity: passed.
- R15 validation shell script syntax: passed.
- ZIP integrity: passed.

## Important limits

R15 does **not** claim a complete Upgrade activation. The smoke uses the real Coordinator `prepare()`, real Previous `preserve()`, real Staged `stage()`, and real disk Durable Journal Store, but it does not call the production `activate(... prepared:)` entry point. It therefore does not validate Active three-file replacement, Active Pointer publication, activation recovery, or full transaction-lock continuity across all phases.

The deterministic Host signature checker and Mach-O metadata reader are test-only. The previous-release inventory is supplied as a trusted fixture rather than loaded through the production trusted-baseline store. The Host shared-lock adapter is a no-op; Darwin `flock`, Apple SDK/Xcode build, XCTest, launchd/XPC, real RootHide/ElleKit device behavior, and power-loss/kernel-crash behavior remain untested.

Production write gates remain closed.
