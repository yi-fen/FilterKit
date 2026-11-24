# P1-10 Test Report

| Check | Result |
|---|---|
| Swift parse (App, Sources, Tests) | Passed |
| Plugin model + scanner Foundation typecheck | Passed (Linux Swift 6.2; minimal protocol stub) |
| Nested `Filter` dictionary parsing | Passed |
| Top-level filter dictionary parsing | Passed |
| XML and binary plist parsing | Passed |
| Unknown plist key-name retention | Passed |
| Invalid Filter container classification | Passed |
| Wrong filter field type classification | Passed |
| FilterKit management permission gate | Passed |
| packageManager / unknown permission isolation | Passed |
| Invalid pairing permission denial | Passed |
| Localization parity | Passed, 164 keys per language |
| Architecture guard | Passed |
| ZIP integrity | Passed |
| Xcode/iOS SDK build | Not run |
| XCTest execution | Not run |
| Dopamine RootHide/Rootless device validation | Not run |

All P1-10 operations are read-only. No jailbreak files or package-manager databases were changed.
