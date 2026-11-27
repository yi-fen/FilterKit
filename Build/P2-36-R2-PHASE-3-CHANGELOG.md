# P2-36-R2 Phase 3 Changelog

- Added a live AF_UNIX client/server Host integration smoke using the production transport classes.
- The authenticated health request is dispatched through `HelperRequestDispatcher` and checked via an audit sink.
- Added a Phase 3 project/IPC integration static audit.
- Added a macOS/Xcode validation script for Helper build, App build, and XCTest execution.
- Documented Apple-platform validation blockers and the remaining Darwin identity/device acceptance requirements.
- Kept App and Helper association commit Release Gates closed.
