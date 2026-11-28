# P2-44-R9 — Activation Chain Consistency

## Scope

R9 closes the read-after-write gap between the R5 Active three-file transaction and the R6 Active Release Pointer. It does not enable the production write gate or wire the executor into HelperRuntime.

## Source changes

- `HelperRootAtomicActivationExecutor` now performs an independent post-publication verification before deleting transaction backups.
- The verifier reopens the three Active artifacts through `HelperInstallerDescriptorFilesystemObserver`, recomputes their hashes, and reads the Active Release Pointer from its descriptor-relative path.
- Pointer `transactionID`, `releaseIdentifier`, `generation`, and all three artifact hashes must match the committed transaction and independently observed Active bytes.
- When a Durable Journal is present, the verifier additionally requires the same transaction/release/generation, state `.activated`, and no pending operation.
- The activation path passes the updated, persisted `.activated` Journal value to the verifier (not the stale pre-activation `.staged` value).
- Recovery performs the same read-after-write check after it reconciles the Durable Journal and republishes the Pointer. Backups and the internal transaction record remain until verification succeeds.
- The R5 Host harness now includes a narrow filesystem observer shim so the actual executor's post-publication checks run in its Host transaction tests.
- Added R9 activation-chain static audit and combined regression runner.

## Failure behavior

A pointer write or read-after-write verification failure remains indeterminate. The executor does not delete the transaction record or Previous Release backups. Recovery must re-verify Active bytes and republish/verify the pointer before cleanup. Unknown or mismatched state remains fail-closed.
