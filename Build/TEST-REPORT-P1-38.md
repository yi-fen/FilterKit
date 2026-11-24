# P1-38 Test Report

## Executed

- Focused Swift typecheck of SHA256, Helper policy/models, P1-37 release verifier and P1-38 executor: passed.
- `p1-38-root-activation-smoke.swift`: passed.
  - Three fixed destination parents opened without following symlinks.
  - Exact three-artifact release set reverified before activation.
  - Foreign pre-existing destination was rejected without overwrite.
  - First-install deployment completed with executable 0755, manifest 0600, and all hashes verified.
  - Injected interruption after manifest activation was recovered by hash-checked rollback.
  - A subsequent upgrade committed and the durable journal was cleaned.
  - Unknown bytes introduced after another interruption were rejected for manual intervention.
- Full app/source/helper/unit-test Swift parse: passed.
- Project identity and signing configuration verification: passed.
- Architecture structure check: passed (8 required files).
- Localization check: passed (237 matching zh-Hans/en keys).
- ZIP integrity verification: passed.

## Not executed

Xcode/iOS/Darwin compilation, XCTest, Darwin `renameatx_np` runtime behavior, RootHide/Rootless device testing, launchd bootstrap/bootout, code-signature/CDHash verification, release provenance verification, and power-loss testing on physical storage. No live jailbreak paths were touched.

## Release gate

The executor is not wired into the production Helper runtime. `executionEnabled=false` remains in force.
