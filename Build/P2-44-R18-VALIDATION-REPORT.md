# P2-44-R18 Validation Report

## Results

| Validation | Result |
|---|---:|
| R18 Recovery Boundary Host Smoke | 80/80 assertions passed |
| R18 static audit | 16/16 passed |
| R17 recovery fault matrix regression | 54/54 assertions passed |
| R17 static audit | 29/29 passed |
| R16 full Upgrade regression | 28/28 assertions passed |
| R16 static audit | 33/33 passed |
| R15 Store write regression | 16/16 assertions passed |
| R15 static audit | 26/26 passed |
| Swift syntax parse | 274/274 source and test files passed |
| Project.yml YAML parse | passed |
| English localization | 519 unique keys; no duplicates |
| Simplified Chinese localization | 519 unique keys; no duplicates |
| Localization key parity | passed |
| `plutil -lint` for both localization files | passed |
| Shell syntax for R15-R18 smoke runners | passed |

## R18 coverage

The R18 Host smoke exercised the production Coordinator, Durable Journal Store, Previous Store, Staged Store, prepared activation overload, and durable recovery overload. It covered all three Active rename crash positions, progress-Journal interruption, committed-Journal interruption, Pointer publication before/after rename, missing Previous backup, unknown Active bytes, repeated recovery, and absence of service-start operations.

## Important limits

- This is Linux Host validation, not an iOS/Xcode build or XCTest run.
- Host-only deterministic signature and Mach-O metadata fixtures remain in use; they do not validate production Ed25519 or Apple code signatures.
- Service peer identity and stopped-state evidence are Host fixtures; no OS-derived audit-token credentials or live launchd observer were exercised.
- The Host descriptor observer and shared acceptance-lock adapter are not Darwin production implementations.
- No Darwin rename semantics, launchd/XPC integration, RootHide/ElleKit device deployment, power-loss testing, or real Helper lifecycle acceptance was performed.
- Production write gates remain closed. This phase does not authorize real writes.
