# P1-15 Test Report

| Check | Result |
|---|---|
| Full Swift syntax parse (App, Sources, Tests) | Passed |
| Manifest/association/backup models Foundation typecheck | Passed |
| Read-only scanner and Mach-O dependencies Foundation typecheck | Passed (protocol/environment stubs only for unrelated app-level dependencies) |
| Schema 1 -> 3 compatibility smoke | Passed; legacy soft association defaults enabled; preview does not write |
| Schema 3 encode/decode smoke | Passed; disabled state preserved |
| Schema 1/2/3 validation XCTest source typecheck | Passed |
| Backup compatibility XCTest source typecheck | Passed |
| Backup schema 1/2 compatibility smoke | Passed; schema 1 defaults enabled and schema 2 preserves disabled state |
| XCTest execution | Not run; no Xcode project test host in this Linux environment |
| Xcode / iOS SDK build | Not run; Xcode/iOS SDK unavailable |
| RootHide / Rootless device validation | Not run |
| Manifest migration filesystem write | Not implemented by design |

The smoke executable was compiled with Swift/Foundation and exercised legacy migration preview plus schema 3 encode/decode. This is not an Xcode build or XCTest execution.
