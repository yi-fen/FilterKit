# P1-09 Test Report

| Check | Result |
|---|---|
| Swift source parse (App, Sources, Tests) | Passed |
| Plugin scanner + dpkg provider Foundation typecheck | Passed (Linux Swift 6.2, minimal stubs for app-only protocols/environment) |
| Exact dpkg `.list` ownership smoke test | Passed |
| Package-manager ownership classification | Passed |
| Dylib/plist pairing smoke test | Passed |
| Case-insensitive duplicate basename detection | Passed |
| Ambiguous directory fail-closed | Passed |
| Localization parity | Passed, 139 keys per language |
| ZIP integrity | Passed |
| Xcode/iOS SDK build | Not run |
| XCTest execution | Not run |
| Dopamine RootHide/Rootless device validation | Not run |
| Runtime loaded-image inspection | Not implemented in P1-09 |

All P1-09 scanning and ownership operations are read-only. No dpkg command was invoked and no jailbreak files were changed.
