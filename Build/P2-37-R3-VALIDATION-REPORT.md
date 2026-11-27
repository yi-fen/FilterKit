# P2-37-R3 Validation Report

## Environment

- Host: Linux x86_64
- Swift compiler: 6.2.1
- Xcode / Apple iOS SDK: unavailable in this environment

## Executed checks

| Check | Result |
|---|---:|
| P2-37-R3 activation consistency Host Smoke | **11/11 passed** |
| P2-37-R3 static audit | **25/25 passed** |
| P2-37-R2 Helper identity audit | **29/29 passed** |
| P2-37-R1 App-state audit | **15/15 passed** |
| P2-37 original activation audit | **25/25 passed** |
| P2-36-R1 association audit | **12/12 passed** |
| P2-36-R2 Phase 2 transaction audit | **17/17 passed** |
| P2-36-R2 Phase 3 IPC audit | **18/18 passed** |
| P2-36-R2 Phase 4 Apple-gate audit | **13/13 passed** |
| Swift frontend parse of all `Sources` and `App` files | Passed |
| Focused semantic typecheck: scanner, identity resolver, registry | Passed with Host-only platform shims for SwiftUI/HelperPolicy/provider protocols |
| `AppPluginActivationStateResolverTests.swift` (15 XCTest methods) source typecheck | Passed against a temporary `FilterKit` module; XCTest execution remains pending on Apple |
| `Project.yml` YAML parse | Passed |
| Shell syntax checks | Passed |
| English localization duplicate-key check | 410 keys, 0 duplicates |
| Simplified Chinese localization duplicate-key check | 410 keys, 0 duplicates |

The focused semantic typecheck validates the changed model/scanner/registry/resolver code paths with minimal Linux-only shims for unavailable Apple/SwiftUI dependencies. It is not an Xcode/iOS SDK build.

## Host Smoke coverage

1. Hard-bound App can be disabled in Filter while its permanent binding remains.
2. Two soft-associated Apps show independent enabled/disabled states.
3. Each App receives a separate preview identity.
4. Expired Helper evidence locks preview.
5. A changed manifest byte hash invalidates Helper evidence.
6. A disabled soft association still present in Filter locks affected App controls.
7. Package-manager/third-party ownership is rejected.
8. Unknown scanner ownership is locked without Helper evidence.
9. Unknown scanner ownership can be considered only after valid Helper proof is attached.
10. Preview ledger separates the same plugin across Apps.
11. A new scan snapshot clears stale previews.

## Not executed / still required

- XcodeGen project generation and Xcode/iOS SDK compilation.
- XCTest through Apple's XCTest Runner.
- Real Darwin `LOCAL_PEERTOKEN` / `csops` identity verification.
- Signed App + signed Helper end-to-end IPC on a supported Apple device.
- RootHide / ElleKit device validation.
- Device-level file replacement race and Helper process-restart validation.

No Apple-platform or device pass is claimed by this report.
