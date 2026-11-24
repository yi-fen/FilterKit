# P1-07 Test Report

- Swift source parser across project Swift files: PASS.
- Swift 5 language-mode typecheck of App models, inventory query, cache provider, and LaunchServices provider fallback branch with protocol stubs: PASS.
- Executable smoke test: PASS.
  - Confirmed default inventory filtering hides system and unclassified apps.
  - Confirmed name search is case-insensitive and Bundle ID search works.
  - Confirmed enabling system-app visibility includes all classifications.
  - Confirmed cache hit within TTL avoids another source scan.
  - Confirmed explicit refresh bypasses cache.
  - Confirmed TTL expiry and explicit invalidation trigger a fresh scan.
- zh-Hans / en localization parity: PASS (75 matching keys; no duplicates).
- Architecture structure check: PASS.
- Project identity/configuration check: PASS.
- ZIP integrity: pending.
- Xcode/iOS SDK build and XCTest execution: NOT RUN (Xcode unavailable).
- Live LaunchServices enumeration on Dopamine RootHide / Rootless: NOT RUN.
