# P2-27 Validation Report

## Host checks executed

- Swift syntax parse across App, Sources, HelperRuntime, Tests, and Build/Scripts Swift files: PASS.
- Focused Linux Swift typecheck for Helper models, trust provisioning, installer provisioning, deployment route validation, and SHA-256 support: PASS.
- Compiled and executed `Build/Host/run-p227-identity-compatibility-smoke.sh`: PASS.
  - matching App/Helper pins and UID/GID accepted;
  - mismatched App CDHash rejected;
  - non-root Helper UID rejected;
  - older schema-1 App trust JSON without optional UID/GID fields remains decodable.
- P2-07 through P2-27 static gate scripts: PASS (all scripts).
- P2-25 authorized recovery smoke: PASS.
- P2-12 AF_UNIX Health smoke: PASS.
- P2-15 audit sink smoke: PASS.
- Python syntax compilation for provisioning/audit scripts: PASS.
- Shell syntax check for the P2-27 smoke runner: PASS.
- Project.yml YAML parse: PASS.
- ZIP archive integrity: checked at packaging.

## Platform checks not executed

- `p227_identity_provisioning_audit.py` final signature audit: BLOCKED on this Linux host because Apple `codesign` is unavailable. The script correctly exits with `BLOCKED: run on macOS with Apple's codesign tool`.
- XcodeGen / Xcode project generation and iOS SDK build: not run; no Apple toolchain is available.
- Darwin-specific `csops`, `proc_pidinfo`, `LOCAL_PEERTOKEN`, `getpeereid` runtime behavior: not validated here.
- RootHide device App-to-Helper socket connection and real installed UID/GID observations: not tested.
- XCTest suite: not run.

## Security state

No production execution or plugin-association commit gate was enabled. The App trust configuration remains an unsigned configuration resource protected by the final App code signature; it is not a standalone cryptographic release attestation. The Helper's root-owned manifest remains the enforcement point for the App's exact CDHash. Target UID/GID must be measured on the RootHide device before running the macOS audit.
