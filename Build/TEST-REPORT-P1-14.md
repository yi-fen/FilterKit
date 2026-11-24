# P1-14 Test Report

| Check | Result |
|---|---|
| Full Swift syntax parse (App, Sources, Tests) | Passed |
| Association plan + resolver + editor Foundation typecheck | Passed |
| Filter.plist preview + existing parser + SHA-256 Foundation typecheck | Passed |
| Association resolver standalone smoke (hard-bound, soft enabled/disabled, missing App) | Passed |
| Hard-bound toggle denial standalone smoke | Passed |
| Non-manageable plugin edit denial standalone smoke | Passed |
| Non-mutating plist preview standalone smoke | Passed |
| Localization parity | Passed; 198 keys in each language, no duplicates |
| XCTest execution | Not run; Xcode/iOS test host unavailable |
| Xcode / iOS SDK build | Not run; Xcode/iOS SDK unavailable |
| RootHide / Rootless device validation | Not run |
| Filter.plist source-semantic verification | Inconclusive; public repository overview/package index does not establish the matching semantics required for safe mutation |

The standalone smoke executable was compiled with Swift/Foundation against the relevant project models and exercised association resolution, authorization denials, and preview-only plist behavior. This is not an Xcode build or XCTest execution.
