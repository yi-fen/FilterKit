# P2-43-R17 Validation Report

## Baseline

- Input: `FilterKit-P2-43-R16-Source.zip`
- Expected SHA-256: `00b515a696689c87ea7e99542c12596c3ae67269bab2d8c75b3932a46f690e9d`
- Baseline ZIP integrity: passed before extraction.
- R16 archive and workspace were not modified.

## R17 validation actually run

- Swift syntax parsing: 272/272 source and test Swift files passed.
- R17 static acceptance audit: 14/14 passed.
- R10 transaction host smoke: passed.
- R11 crash recovery host smoke: 17/17 passed.
- R12 descriptor filesystem host smoke: 18/18 passed.
- R13 recovery host smoke: 13/13 passed.
- R14 preflight host smoke: 14/14 passed.
- R15 security host smoke: 16/16 passed.
- R16 dry-run host smoke: 21/21 passed.
- R1–R17 static audits: passed. R1–R16 historical audits were re-run against the extracted source tree.
- `Project.yml` YAML parsing: passed.
- English localization: 519 keys, 519 unique.
- Simplified Chinese localization: 519 keys, 519 unique.

## Not run / not claimed

- XCTest was not run.
- Full iOS or Helper target compilation was not possible: this host has Swift 6.2.1 on Linux and no Xcode/Apple SDK.
- No Darwin `flock`/launchd/XPC runtime test was run.
- No RootHide / ElleKit device acceptance was run.
- No real power-loss or kernel-crash injection was run.
- The acceptance runner composes the existing concrete preflight API, but the platform service-observation adapter must still call the R15 authenticated observer with OS-derived peer identity. The JSON digest is not cryptographic authorization.

## Security posture

All production write gates remain closed. R17 adds a read-only acceptance/reporting path only.
