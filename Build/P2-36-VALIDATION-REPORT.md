# P2-36 Validation Report

## Host checks

Run:

```sh
Build/Host/run-p236-association-persistence-smoke.sh
```

This performs 18 static contract checks. It is not a substitute for compiling the iOS app/helper or executing XCTest on an Apple toolchain.

## Not performed

- XcodeGen / xcodebuild / iOS SDK build
- XCTest on Apple platforms
- signed App/Helper artifact validation
- RootHide device Helper IPC
- root-owned Filter.plist + manifest transaction and crash recovery
- ElleKit runtime injection validation

## Release safety

The association commit gates in the App coordinator and Helper dispatcher remain closed (`false`).
