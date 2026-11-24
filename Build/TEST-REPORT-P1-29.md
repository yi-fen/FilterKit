# Test Report — P1-29

| Check | Result |
|---|---|
| Full Swift source parse | PASS |
| Helper + Runtime Linux Swift typecheck | PASS |
| Root-side staging reader smoke | PASS |
| Symlinked staging file rejection | PASS |
| Staging path traversal rejection | PASS |
| Real backend first-install route evidence | PASS |
| Root-side package ownership detection from dpkg info list | PASS |
| Staging SHA-256 verification | PASS |
| Plist parse and synthetic Mach-O identity validation | PASS |
| First-install hard-bound/soft association metadata digest binding | PASS |
| Metadata Codable round trip | PASS |
| Backend mutation gate remains closed | PASS |
| P1-21 runtime regression smoke | PASS |
| P1-22 safe executor regression smoke | PASS |
| P1-23 ownership verifier regression smoke | PASS |
| P1-23 transaction recovery planner regression smoke | PASS |
| P1-24 bootstrap/recovery regression smoke | PASS |
| P1-25 Dispatcher regression smoke | PASS |
| P1-26 route resolver regression smoke | PASS |
| P1-27 batch protocol regression smoke | PASS |
| P1-28 fake-backend pipeline regression smoke | PASS |
| Project configuration check | PASS |
| Architecture check | PASS |
| Localization parity (225 zh-Hans/en keys) | PASS |
| ZIP integrity | PASS |

The backend smoke uses temporary Linux directories and a synthetic arm64 Mach-O fixture. It verifies real POSIX file reads and ownership-list parsing in the test environment, not RootHide/Rootless device behavior.

Not run: Xcode/iOS SDK build, XCTest, Darwin compilation, iOS code-signing/CDHash validation, launchd integration, actual jailbreak dpkg database inspection, or real TweakInject writes.

P1-29 intentionally does not enable deployment. The production backend performs authorization/preflight only; first-install Manifest + payload atomicity and update three-file transaction/recovery remain release blockers.
