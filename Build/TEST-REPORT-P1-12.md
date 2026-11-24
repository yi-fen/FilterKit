# P1-12 Test Report

| Check | Result |
|---|---|
| Full Swift source parse (App, Sources, Tests) | Passed |
| Identity model + analyzer Foundation typecheck | Passed |
| Scanner + ownership provider Foundation typecheck | Passed |
| Duplicate binary identity smoke test | Passed |
| Same install name / different fingerprint smoke test | Passed |
| Same UUID / different CDHash smoke test | Passed |
| Missing UUID and CDHash remains insufficient, not invented | Passed |
| Identity conflict downgrades management to read-only | Passed |
| Ownership conflict downgrades management to read-only | Passed |
| FilterKit manifest vs dpkg ownership conflict scanner smoke test | Passed |
| Manifest schema 1 backward-compatible file-hash binding | Passed in scanner smoke test |
| Localization parity | Passed, 185 keys in each language; no duplicate keys |
| Xcode / iOS SDK build | Not run (Xcode/iOS SDK unavailable in this environment) |
| XCTest execution | Not run; test cases were added to the Xcode test target |
| RootHide / Rootless device validation | Not run |

The smoke tests above were executed as standalone Swift programs on the available Swift toolchain. They are not a substitute for Xcode XCTest or target-device validation.
