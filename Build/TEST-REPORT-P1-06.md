# P1-06 Test Report

- Swift 6.2.1 Linux typecheck of the new association model and reader with minimal app/scan protocol stubs: PASS.
- Executable association smoke test: PASS.
  - Verified manifest plugin UUID is used as the stable association record identity.
  - Hard-bound source app absent from the installed-app inventory remains recorded as the hard-bound identity.
  - Missing hard-bound app is not migrated to an installed soft-associated app.
  - Installed soft association appears in effective Bundle IDs.
  - Missing soft association is separately reported.
  - Result is marked read-only.
- Chinese/English localization key parity: PASS (69 keys in each; no duplicate keys).
- Source syntax parse: PASS.
- ZIP integrity: PASS after packaging.
- Xcode/iOS SDK build and XCTest execution: NOT RUN (Xcode unavailable).
- Dopamine RootHide / Rootless live app inventory and manifest validation: NOT RUN.
