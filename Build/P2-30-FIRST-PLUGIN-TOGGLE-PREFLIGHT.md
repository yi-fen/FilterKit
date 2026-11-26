# P2-30 — First Real Plugin Toggle Preflight

## Scope

P2-30 adds a read-only preflight for the exact signed FilterKit App and Helper artifacts intended for the first RootHide device trial. It captures Apple's codesign verification output, signed identifiers, CDHashes, App bundle identifier, and the embedded `FilterKit-Helper-AppTrust.json` payload. It does not install, launch, connect to a device, edit ElleKit configuration, or write to jailbreak paths.

## Run on macOS

```sh
python3 Build/scripts/p230_signed_artifact_preflight.py \
  --app /path/to/FilterKit.app \
  --helper /path/to/FilterKit-Helper.app \
  --output Build/DeviceAcceptance/p230-signed-artifacts.json
```

The helper path must point to the actual signed Helper bundle. Retain the generated JSON and the exact App/Helper artifacts together. A successful report proves only that the local artifacts pass the invoked codesign checks and that the embedded trust JSON can be parsed. It does not prove that the installed device copies are identical, that App↔Helper IPC works, or that ElleKit injects the test dylib.

## First-toggle sequence after preflight

1. Build/sign App and Helper with the intended release identity.
2. Run the preflight and review both CDHashes, identifiers, Team IDs, and embedded AppTrust JSON.
3. Install only on a disposable RootHide + ElleKit test device.
4. Capture live peer UID/GID/CDHash and Helper health IPC evidence.
5. Choose one FilterKit-owned test plugin and one non-system disposable target App.
6. Perform a separately authorized, instrumented device experiment; verify actual target-process image loading, not merely a successful configuration write.
7. Disable, restart the target, verify the dylib is absent, and test interruption recovery and audit durability.

## Release boundary

No global or per-feature production mutation switch is opened in P2-30. A successful artifact preflight is not sufficient authorization. The existing release gate and Helper execution gates remain closed. No true injection result is claimed because no signed Apple build or RootHide device is available in this execution environment.

## Validation performed here

- Python syntax compilation and unit tests for the preflight's platform-independent helpers (where applicable).
- Existing P2-29 evidence validator tests and P2-28 toggle smoke/static audit.
- ZIP integrity check.

macOS codesign execution, Xcode build, installation, live IPC, ElleKit toggle, process-level injection observation, and recovery on hardware remain unperformed and must be recorded from the actual test device.
