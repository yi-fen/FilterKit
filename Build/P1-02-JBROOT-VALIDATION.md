# P1-02 — JBROOT candidate validation

## Purpose

P1-02 strengthens P1-01 path discovery. A path is no longer treated as a usable JBROOT merely because it exists. It must be a readable directory and expose the required structural markers `usr/` and `usr/lib/` as readable directories.

## Candidate sources

- Rootless candidates: `/var/jb` and `/private/var/jb`.
- RootHide candidates: `.jbroot-*` children discovered beneath `/var/containers/Bundle/Application`.

These remain discovery heuristics, not universal path guarantees. The app sandbox may hide paths or report inaccessible paths as missing. No candidate is promoted to a supported deployment path by this phase.

## Canonicalization and ambiguity

- Existing candidates are normalized through Foundation URL standardization and symlink resolution.
- Candidate aliases resolving to the same canonical path are collapsed before ambiguity checks.
- Two distinct structurally valid roots remain ambiguous; no automatic winner is selected.
- RootHide vs Rootless classification comes from the candidate source, not from arbitrary string matching against the resolved path.

## Structural validation

Required checks:

- candidate exists;
- candidate is a directory;
- candidate is readable;
- `usr` exists, is a directory, and is readable;
- `usr/lib` exists, is a directory, and is readable.

The report preserves per-candidate checks, canonical path, source aliases, symlink evidence, score, and stable detail code. Score is diagnostic only; it is not used to choose between multiple roots.

## Safety

This phase is strictly read-only. It does not create, modify, rename, or delete files; it does not invoke a shell or process; it does not write preferences or jailbreak configuration. A validated root only means that the structural checks passed in the current process context. It does not prove that privileged writes are possible or authorize plugin deployment.

`canDeployFilterKitPlugins` remains false. ElleKit profile and DynamicLibraries validation remain separate gates.

## Tests

`JBRootResolverTests` covers valid structure, multiple distinct roots, symlink alias collapsing, and rejection of incomplete roots. Tests create temporary fixtures only inside the test process and remove them afterward.
