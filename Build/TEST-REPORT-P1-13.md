# P1-13 Test Report

| Check | Result |
|---|---|
| Full Swift syntax parse (App, Sources, Tests) | Passed |
| Strategy models/resolver Foundation typecheck (with minimal dependency stubs) | Passed |
| Default-deny when no profile evidence exists | Passed (standalone smoke) |
| Device validation required before mutation | Passed (standalone smoke) |
| RootHide/Rootless evidence isolation | Passed (standalone smoke) |
| Hard-bound App toggle denial | Passed (standalone smoke) |
| Configuration state does not imply runtime load success | Passed (standalone smoke) |
| Localization parity | Passed; 190 keys in each language, no duplicate keys |
| Xcode / iOS SDK build | Not run (Xcode/iOS SDK unavailable) |
| XCTest execution | Not run; test cases were added |
| RootHide / Rootless device validation | Not run |

The standalone smoke executable exercised the strategy resolver, environment isolation, hard-bound denial, and runtime-state separation. Minimal stubs were used only for unrelated app model dependencies during Foundation typechecking; this is not an Xcode build or full-app typecheck.
