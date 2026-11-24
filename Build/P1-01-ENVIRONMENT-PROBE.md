# P1-01 — Read-only jailbreak environment probe

## Scope

P1-01 introduces a conservative, read-only environment inspection layer. It does not deploy plugins, edit ElleKit configuration, write jailbreak paths, invoke a shell, or infer that a plugin is loaded.

## Detection strategy

- Rootless candidates: `/var/jb` and `/private/var/jb`.
- RootHide candidates: directories beginning with `.jbroot-` under `/var/containers/Bundle/Application`.
- Candidate directory checks use Foundation file APIs only.
- Dynamic-library directory candidates are inspected beneath each discovered root: `usr/lib/TweakInject` and `Library/MobileSubstrate/DynamicLibraries`.
- ElleKit presence candidates are inspected as files beneath discovered roots. Presence does not identify a version or commit.

These are discovery heuristics, not a claim that every Dopamine/RootHide/Rootless release uses these paths. Profile support remains unverified until matched against the exact installed ElleKit source/build and tested on-device.

## Safety behavior

- No file or directory is created, modified, moved, or deleted.
- No process or shell command is launched.
- Ambiguous roots or library directories are not silently selected.
- `canDeployFilterKitPlugins` is always false in this phase.
- `canDiscoverApps` remains false until App Discovery is separately implemented and validated.
- ElleKit version and commit remain unknown unless a later verified metadata reader can establish them.

## Known limitations

- iOS sandbox visibility and jailbreak-specific path translation vary by jailbreak and OS release.
- A missing path may mean absent or inaccessible due to sandbox restrictions.
- This implementation does not yet use jailbreak-specific APIs, package databases, or helper privileges.
- Actual behavior must be tested on supported Dopamine devices before any profile is marked supported.
