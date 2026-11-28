# P2-44-R17 Validation Report

## Baseline integrity

- Input archive: `FilterKit-P2-44-R16-Source.zip`
- Expected SHA-256: `6a91fdd291fd397c2f1681bf6939e78a8e1be6308de9e06c5d7856ba000d87e0`
- Baseline SHA-256 matched.
- `unzip -t` passed before extraction.
- R17 work was performed in a new workspace; R16 archive and workspace were not overwritten.

## Results

| Validation | Result |
|---|---:|
| R17 recovery fault-matrix Host smoke | 54/54 |
| R17 static recovery audit | 29/29 |
| R16 full Upgrade Host smoke regression | 28/28 |
| R16 static full Upgrade audit regression | 33/33 |
| R15 Store write Host smoke regression | 16/16 |
| R15 static Store write audit regression | 26/26 |

## R17 recovery behavior exercised

All three Active artifact replacement positions were fault-injected after replacement. Each recovery restored the exact prior bytes for executable, deployment manifest, and launch daemon, moved the Durable Journal to `manualIntervention`, and cleared the completed rollback transaction evidence. A second recovery returned no pending transaction.

A separate unknown-Active-bytes case verified that recovery throws `recoveryRequiresManualIntervention`, leaves the unknown Active executable bytes untouched, persists Durable Journal `manualIntervention`, and remains blocked on repeated recovery.

The source audit verifies complete three-artifact preflight precedes `rollingBack`, checks Active and backup hashes, requires sufficient Previous backup evidence, performs no `unlinkat` during preflight, and marks both activation record and Durable Journal for manual intervention on unknown/insufficient evidence.

## Environment limitations

The tests ran on Linux with Swift 6.2.1 and root-owned temporary Host fixtures. The production transaction executor and stores were compiled and executed, but several security/platform dependencies were represented by Host adapters: deterministic test signature verification, test Mach-O metadata, fixture peer identity/stopped-state report, simplified descriptor observer, and no-op shared acceptance lock.

No `xcodebuild`, Apple SDK, XCTest, Darwin `flock`/rename semantics, launchd/XPC, OS-derived audit-token identity, production code-signature validation, or RootHide/ElleKit device acceptance was available. The passing Host tests must not be interpreted as device acceptance.

## Gate status

Production activation/write gates remain closed. No live Helper deployment, launchd action, service start/restart, or jailbreak filesystem write was performed.

## Repository-wide checks

- `swiftc -parse` passed for all 274 Swift files under `Sources` and `Tests`.
- `Project.yml` parsed successfully as YAML.
- English and Simplified Chinese localization files each contain 519 unique keys; key parity passed.
- R17 validation runner and R17 smoke runner passed `bash -n`.
- R17 audit Python file passed `py_compile`.
