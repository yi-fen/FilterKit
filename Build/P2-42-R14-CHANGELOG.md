# P2-42-R14 — Association and Uninstall Transaction Integrity

## Scope

R14 continues from the verified R13 source. The page boundary remains unchanged:

- APP is the only UI surface for first injection and per-App enable/disable.
- Plugin is limited to editing Additional App Associations and requesting plugin uninstall.
- Plugin may display activation state, but it does not write activation bits.

## Changes

### 1. Schema-4 binding topology support in Helper mutation

- Association mutation authorization now accepts both schema-3 manifests and schema-4 manifests with a valid, consistent binding topology.
- Schema-4 `fixedOwnerIsEnabled` is preserved when Plugin-page association membership is changed.
- The association planner now takes the fixed-owner activation bit into account when checking the exact `Filter.plist` Bundle set.
- Retained Additional App Association activation bits remain immutable during Plugin-page edits; newly added associations remain disabled.
- Schema-4 metadata is reconstructed with matching `bindingTopology`, `softAssociations`, and `softAssociatedBundleIdentifiers` mirrors.
- The two-file transaction validates staged schema-3/schema-4 binding metadata before replacement.

### 2. APP activation compatibility for fixed owner

- Schema-4 fixed-owner activation can be enabled/disabled through the existing APP-side activation request path.
- A schema-3 fixed owner retains its historical enabled interpretation. When APP explicitly disables that fixed owner, the Helper upgrades the manifest to schema 4 and persists `fixedOwnerIsEnabled = false` atomically with the Filter.plist change.
- Subsequent activation changes preserve the schema-4 topology.
- Schema-3 activation of the fixed owner when already enabled remains an idempotent no-op.

### 3. Uninstall recovery coverage

- Added fault-injection coverage for every three-file uninstall journal phase: prepared, moving dylib, moving plist, moving manifest, and committed.
- Pre-commit interruption must restore all three original files.
- Post-commit interruption must finish deleting all three quarantined files.
- Added a last-boundary authorization-denial test proving that no journal or file movement occurs when fresh authorization fails.

### 4. Association planner coverage

- Added multi-App removal coverage proving retained enabled/disabled states are preserved.
- Added fixed-owner-disabled cases proving association removal does not accidentally re-enable the fixed owner.
- Existing Classes/Executables ambiguity checks remain fail-closed.

## Safety

No production release gate was opened. Helper association commit, APP activation commit, deployment, and uninstall execution remain disabled pending signed build, RootHide/ElleKit device acceptance, and recovery validation.
