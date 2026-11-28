# P2-44-R3 — Staged Release Write Qualification

## Scope

R3 adds a narrowly scoped, root-owned quarantine store for signed Helper release artifacts. It is separate from `HelperInstallerProvisioningBundle.stagingRootPath`, which remains the App-owned plugin-payload staging directory.

The fixed release staging directory is:

`<JBROOT>/Library/FilterKit/Helper/StagedReleases`

It must be provisioned in advance as `root:root`, mode `0700`. The store does not create or chmod this base directory.

## Implementation

- Added `HelperInstallerStagedReleaseStore.swift`.
- Accepts only `HelperPreparedRootInstall` produced by the trusted installer preparation flow.
- Rebinds the provisioning-envelope SHA-256 and checks release ID/generation.
- Re-runs the canonical three-artifact `HelperRootReleaseSet` verification.
- Parses the executable as Mach-O and checks signed CodeDirectory extraction, Team ID, and the provisioned Helper CDHash.
- On Darwin, holds the same shared installer acceptance lock used by startup/recovery while staging or inspecting.
- Requires a durable Journal with a matching `stageRelease` intent before creating a staging transaction directory.
- Creates a UUID-named root-owned `0700` transaction directory with descriptor-relative `mkdirat`.
- Writes three artifacts through exclusive no-follow temporary files, applies exact modes, fsyncs files, atomically renames, and fsyncs directories.
- Reopens and rehashes every staged artifact after writing.
- Advances the Durable Journal from pending `stageRelease` to `staged` only after all staged bytes and directories have been synchronized.
- If the staged files are durable but Journal completion cannot be proven, preserves the files and reports `journalCommitIndeterminate`.
- Read-only inspection classifies missing, complete, partial, and mismatched staged sets; checks exact directory inventory, file mode, ownership, hard-link count, and read stability. It never repairs, activates, or deletes a partial release.

## Deliberate boundaries

- This is a staging primitive, not an activation executor.
- It does not call launchd, bootstrap the Helper, change Active artifacts, update Active Release Pointer, or enable production execution gates.
- The base StagedReleases directory must be created by a separately trusted provisioning step; R3 does not invent or silently create production directory ownership/mode.
- The host smoke uses small model shims for the trusted-preparation and Durable Journal APIs while compiling the real staged store, SHA-256 implementation, and Mach-O parser. It does not constitute a full iOS/Helper target build or Darwin device acceptance.
