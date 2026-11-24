# Test Report — P1-28

| Check | Result |
|---|---|
| Full Swift source parse | PASS |
| Helper pipeline + dispatcher Linux typecheck | PASS |
| First-install pipeline simulation | PASS |
| Existing FilterKit update pipeline simulation | PASS |
| Unknown ownership rejection | PASS |
| Route-specific authorization failure | PASS |
| Batch receipt integrity rejection | PASS |
| P1-27 batch protocol regression | PASS |
| Project configuration | PASS |
| Architecture checks | PASS |
| Localization parity (225 zh-Hans/en keys) | PASS |
| Local static build checks | PASS |

The pipeline smoke uses a fake backend. It validates orchestration and invariants, not actual root-side package ownership, manifest creation/verification, staging file reads, or filesystem writes.

Not run: Xcode/iOS SDK build, XCTest, Darwin compilation, jailbreak-device validation, launchd integration, or real TweakInject writes. All execution release gates remain disabled.
