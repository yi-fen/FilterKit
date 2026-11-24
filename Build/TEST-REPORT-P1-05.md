
# P1-05 Test Report

- Scanner/model SHA-256 typecheck on Swift 6.2.1 Linux with minimal protocol/environment stubs: PASS.
- Executable smoke checks: PASS.
  - SHA-256 `abc` known vector.
  - Exact-stem `.dylib` + `.plist` pairing.
  - Missing plist -> `orphanDylib`.
  - Invalid plist -> `invalid`.
  - Ambiguous directory -> no scan and no selected path.
  - Valid same-stem `.fk.json` with both matching SHA-256 values -> `filterKit` ownership and hard-bound App metadata.
- Chinese/English localization key parity: see packaging validation.
- ZIP integrity: see packaging validation.
- Xcode build and XCTest execution: NOT RUN (Xcode unavailable).
- Jailbreak-device validation: NOT RUN.
