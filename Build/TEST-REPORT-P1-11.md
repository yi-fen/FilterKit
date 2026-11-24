# P1-11 Test Report

| Check | Result |
|---|---|
| Swift parse (App, Sources, Tests) | Passed |
| Mach-O reader Foundation typecheck | Passed |
| Plugin scanner + model Foundation typecheck | Passed |
| Thin arm64e synthetic Mach-O smoke test | Passed; install name, 1.2.3 current version, 1.0.0 compatibility version, UUID extracted |
| Fat Mach-O synthetic smoke test | Passed; arm64 and arm64e slices enumerated |
| CodeDirectory/SuperBlob synthetic CDHash smoke test | Passed; 40-hex-character CDHash produced |
| Plugin scanner integration smoke test | Passed; Mach-O metadata attached to scan item |
| dpkg exact ownership + Version smoke test | Passed; package identifier and Version 3.4-2 returned |
| Localization parity | Passed, 173 keys in each language |
| Full Swift syntax parse | Passed |
| Xcode/iOS SDK build | Not run (no Xcode/iOS SDK in this environment) |
| XCTest execution | Not run |
| Dopamine RootHide/Rootless device validation | Not run |

CDHash parsing is metadata extraction only; it is not signature trust validation. All P1-11 file and package database operations remain read-only.
