# P2-44-R16 Validation Report

## R16 results

- Full Upgrade Host Smoke: **28/28 assertions passed**.
- R16 full Upgrade static integration audit: **33/33 passed**.
- R15 real Store write smoke regression: **16/16 passed**.
- R15 static integration audit regression: **26/26 passed**.
- R16 shell runner syntax: passed.
- Swift syntax parse: **274/274** `Sources` + `Tests` files passed.
- `Project.yml` YAML parse: passed.
- English localization: **519 unique keys**, no duplicates.
- Simplified Chinese localization: **519 unique keys**, no duplicates.
- English/Chinese key parity: passed.
- ZIP integrity: passed.

## R16 Host assertions

1. Production Coordinator `prepare()` creates a signed-test Prepared Upgrade.
2. Real Previous Store preserves actual Active bytes and advances the disk Journal.
3. Real Staged Store writes and reopens the exact verified release bytes.
4. Durable Journal reaches `staged` before activation intent.
5. Partial Previous preservation remains partial and retains pending intent.
6. Partial Stage remains partial and retains pending intent.
7. The production `activate(... prepared:)` overload commits the same Transaction ID.
8. Durable Journal advances to `activated`.
9. All three Active destinations contain the staged bytes.
10. Active Pointer binds Transaction ID, Release ID, Generation, and all three observed hashes.
11. A second Upgrade injects failure before Pointer rename after Active/Journal commit.
12. Recovery republishes the Pointer, finalizes the committed Active set, and clears transaction evidence.
13. A second recovery is idempotent.

## Important limits

- The signature checker and Mach-O metadata reader are deterministic Host fixtures, not production Ed25519 or Apple code-signature validation.
- The service peer and stopped-state report are Host fixtures. The production Observer validation policy is compiled and executed, but the OS-derived peer credentials and live launchd observation are not.
- The descriptor observer used by the activation executor is a simplified Host adapter; it is not the production Darwin descriptor observer.
- The shared acceptance-lock adapter used by the Store layer is a no-op Host shim. The activation executor's own persistent root lock and actual filesystem operations run on Linux, not Darwin.
- R16 tests a complete successful Upgrade and the committed-Active/Pointer-failure recovery path. It does not claim every individual Active rename crash boundary, true power-loss durability, or kernel-crash behavior has been exhaustively tested.
- No Xcode/Apple SDK build, XCTest, Darwin `flock`/rename acceptance, launchd/XPC validation, or RootHide/ElleKit device acceptance was performed.

Production write gates remain closed.
