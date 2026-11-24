# P1-20 Test Report

## Automated checks

- Full project Swift syntax parse (`App`, `Sources`, `Tests`): PASS.
- Helper manifest/IPC/handshake/audit models + replay guard + coordinator + POSIX transport Foundation typecheck on Linux Swift 6.2.1: PASS.
- Standalone AF_UNIX client/server integration smoke: PASS.
  - server bind/listen and client connect
  - kernel peer credentials via Linux `SO_PEERCRED`
  - injected test CDHash identity provider + UID/CDHash trust policy
  - nonce hello/helloAck exchange
  - framed health request/response
  - per-connection authenticated context
  - duplicate requestID rejected by server replay guard
- XCTest source expanded in `HelperIPCAndPolicyTests.swift`; XCTest was not executed.
- Xcode/iOS SDK build: NOT RUN (not available in this environment).
- Darwin/iOS compile of `getpeereid`, `LOCAL_PEERPID`, and private `csops` provider: NOT RUN.
- RootHide / Rootless device tests: NOT RUN.

## Safety checks

- `HelperDeploymentCoordinator.executionReleased` remains `false`.
- Safe Helper manifest template remains `executionEnabled = false`.
- Client and server reject by default if no peer identity provider is configured.
- Socket permissions are not treated as identity proof.
- Server refuses to auto-unlink an existing socket path.
- Server only accepts bounded framed messages, a fresh nonce handshake, health/operation request types, and exact inner/outer request ID binding.
- Server enforces a maximum of 8 concurrent connections and 5-second connection I/O timeout.
- Replay guard is process-local (10 minutes / 4096 IDs); persistence across daemon restart is not implemented.
- Audit data model is bounded, but persistent root-owned audit writer/rotation is not implemented.
- No launchd plist, root Helper executable target, install/uninstall script, or root filesystem writer was added.
- No TweakInject, plugin, plist, dpkg database, or target App file was modified.

## Important limitations

- Linux integration smoke validates the POSIX protocol path and test credential adapter only; it does not validate Darwin/iOS kernel credential APIs.
- Darwin `csops` provider is based on XNU's `CS_OPS_CDHASH` interface and requires on-device verification. Peer PID followed by csops is not an atomic audit-token snapshot; pidversion/audit-token binding remains open.
- The server is a reusable listener implementation, not an installed privileged daemon.
