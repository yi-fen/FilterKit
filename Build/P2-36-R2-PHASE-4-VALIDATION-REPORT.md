# P2-36-R2 Phase 4 — Validation Report

## Status: PREPARATION COMPLETE / APPLE DEVICE ACCEPTANCE BLOCKED

The Phase 4 work package is prepared from the uploaded Phase 3 baseline. This environment is Linux x86_64 with Swift 6.2.1; `xcodebuild`, `xcodegen`, `xcrun`, Apple SDKs, signing identities, and a RootHide/ElleKit device are unavailable. Consequently, no Apple-platform build, XCTest Runner, signed install, or Darwin runtime claim is made.

## Results executed in this workspace

| Check | Result | Evidence |
|---|---:|---|
| Phase 2 static transaction audit | 17/17 PASS | `Build/scripts/p236r2_phase2_transaction_audit.py` |
| Phase 3 integration static audit | 18/18 PASS | `Build/scripts/p236r2_phase3_integration_audit.py` |
| Phase 4 Apple gate static audit | 13/13 PASS | `Build/scripts/p236r2_phase4_apple_gate_audit.py` |
| Swift parser over Sources/App/HelperRuntime/Tests/Host | PASS | `swiftc -frontend -parse` |
| Project.yml YAML parse | PASS | Python YAML parser |
| Phase 4 Apple validation entry point on Linux | BLOCKED as expected | exits 2 with macOS requirement |
| iPhoneOS / Simulator SDK importer probes | NOT RUN | Requires `xcrun` + Apple SDK |
| FilterKit / FilterKitHelper Xcode build | NOT RUN | Requires Xcode |
| XCTest | NOT RUN | Requires Xcode + Simulator |
| Signed App/Helper verification | NOT RUN | Requires signing pipeline/artifacts |
| Darwin LOCAL_PEERTOKEN + csops runtime | NOT RUN | Requires target Darwin device |
| RootHide/ElleKit App↔Helper device IPC | NOT RUN | Requires target device and deployment |

The Phase 2 Host Smoke was invoked during this pass but the combined validation command exceeded its 120-second execution budget and was terminated before a reliable completion result was captured. Its static audit passed. The prior Phase 2 report in the Phase 3 baseline records the transaction/SIGKILL Host Smoke as passing; this delivery does not upgrade that historical evidence. Phase 3 Host Smoke had passed in the prior Phase 3 validation record; this pass reran its static audit but did not independently rerun the executable smoke.

## Darwin identity review

The source path continues to enforce:

- `getpeereid` UID/GID plus `LOCAL_PEERPID` PID on Darwin;
- `LOCAL_PEERTOKEN` read from the connected socket;
- audit-token euid/egid/pid consistency with socket credentials;
- repeated audit-token snapshot equality around `csops(CS_OPS_CDHASH)`;
- nonempty 20-byte CDHash and trust-pin evaluation;
- required kernel audit-token evidence before Darwin transport accepts a peer.

The compile-only probe was expanded to cover the importer surface for `getpeereid`, `LOCAL_PEERPID`, `LOCAL_PEERTOKEN`, `csops` call signature, and the existing `libproc` calls. A successful Linux parser run does not prove these APIs import/link against Apple's SDK. The macOS script is the required next execution step.

## Release gates

Both production soft-association commit gates remain `false`:

- `HelperDeploymentCoordinator.pluginAssociationCommitReleased = false`
- `HelperRequestDispatcher.pluginAssociationCommitReleased = false`

No real jailbreak configuration was modified and no plugin injection was enabled.

## Exit criteria

Phase 4 remains open until a macOS runner produces successful iPhoneOS and Simulator builds, a passing XCTest `.xcresult`, and a target RootHide/ElleKit device report proving signed App/Helper identity, `LOCAL_PEERTOKEN`, `csops` CDHash pinning, negative-client rejection, restart behavior, and recovery behavior. Keep both release gates closed until that evidence is reviewed.
