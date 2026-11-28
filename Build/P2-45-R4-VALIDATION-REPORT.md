# P2-45-R4 Validation Report

## Status

**DEVICE_ACCEPTANCE_PENDING / HOST_QUALIFICATION_ONLY**

No RootHide device or Apple SDK was available. The device-side end-to-end acceptance was not run. This report does not claim device qualification.

## Work delivered

- Read-only-with-respect-to-JBROOT Darwin device evidence collector. It requires explicit device-validated paths and writes its report only outside JBROOT.
- Device acceptance protocol with 12 mandatory evidence rows (D1–D12).
- Static audit of collector safety and closed production execution gates.
- Repeatable Host regression runner.

## Executed Host results

| Validation | Result |
|---|---:|
| R4 static audit | **12/12** |
| R1 production gate / signing static audit | **10/10** |
| R2 Helper identity / IPC static audit | **30/30** |
| R3 filesystem Host smoke | **24/24** |
| R3 filesystem static audit | **24/24** |
| R18 recovery boundary Host smoke | **80/80** |
| Swift syntax parse | **275/275 files** |
| Shell syntax (`bash -n`) | passed |
| Project.yml YAML parse | passed |
| English localization | 519 unique keys, no duplicates |
| Simplified Chinese localization | 519 unique keys, no duplicates |
| Localization key parity | exact match |
| Both Localizable.strings `plutil -lint` | passed |

The combined Host runner exceeded the 300-second execution limit during its final sequential per-file Swift parse loop. The Swift parse was then executed separately as a single `swiftc -parse` invocation and all 275 files passed. All preceding R1/R2/R3/R18 checks were observed passing before the timeout.

## Unresolved blockers

- R1: actual Apple SDK build/signing; Helper target still sets `CODE_SIGNING_ALLOWED: NO`.
- R2: real launchd Helper deployment, kernel peer identity and IPC round-trip.
- R3: actual JBROOT ownership/mode, APFS exclusive rename/fsync and reboot persistence.
- R4: all D1–D12 device acceptance rows.

## Gate decision

All production write gates remain closed. P2-45-R5 is not authorized until device evidence is collected and reviewed and R1/R2/R3 blockers are closed.
