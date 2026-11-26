# P2-04 — Helper Plugin Filter Mutation Authorization

## Baseline and scope

- Baseline: P2-03 Association UI & Configuration Preview.
- Adds an authenticated, path-free Helper request for a narrowly-scoped FilterKit-owned plugin association change.
- The Helper independently re-reads ownership evidence, package-manager ownership, the deployed plist and Schema 3 manifest.
- The Helper prepares exact replacement plist + manifest bytes in memory and returns only status and hashes to the App.
- This phase does **not** write, rename, delete, terminate an App, respring, or claim injection success. The atomic commit is P2-05.

## Protocol

New IPC message types:

- `pluginFilterMutationPrepareRequest`
- `pluginFilterMutationPrepared`

The request carries only:

- request and plugin UUIDs;
- enable/disable intent;
- exact dylib/plist leaf names;
- target Bundle ID;
- expected current plist and manifest SHA-256 values;
- timestamp.

It carries no absolute path, relative path, replacement bytes, owner, mode, or authorization assertion. The Helper validates the request ID against the authenticated envelope, freshness, replay protection and the clean-recovery state.

## Helper-side authorization

`HelperPluginFilterMutationAuthorizer`:

1. Requires effective UID 0.
2. Resolves package-manager ownership from configured root-owned dpkg info directories; package-owned or unavailable evidence fails closed.
3. Runs `HelperOwnershipProofVerifier` against the exact deployed dylib, plist and `.fk.json` manifest.
4. Reopens the exact plist and manifest using directory-relative `openat` with `O_NOFOLLOW` and verifies root ownership, file type, mode and size.
5. Compares the caller's expected hashes to the freshly-read bytes to prevent stale UI state from authorizing a change.
6. Requires Schema 3 manifest identity and matching plugin UUID / exact filenames.
7. Keeps the hard-bound App immutable.
8. Uses the pinned RootHide filter planner; a disable is blocked if alternate Classes or Executables match dimensions remain.
9. Requires the existing `Bundles` set to agree with the manifest's hard-bound App plus enabled soft associations. Unexpected/global rules are not silently normalized.
10. Updates the soft-association enabled state and the manifest's plist hash in the in-memory proposal.

The response contains only disposition, reason code and before/after hashes. The prepared bytes remain inside the Helper process.

## Safety boundaries

- `HelperRequestDispatcher.executionReleased` remains `false`.
- `HelperDeploymentCoordinator.executionReleased` remains `false`.
- `HelperProductionDeploymentBackend.executionReleased` remains `false`.
- The new prepare request is read-only; it does not use the deployment execution release gate because it cannot mutate files.
- Existing third-party/package-manager plugins remain non-manageable.
- No arbitrary path or plist payload is accepted from the App.
- No automatic recovery mutation is performed.
- No runtime injection state is inferred from a prepared configuration.

## Known limitations / next stage

- No atomic two-file commit exists yet for the Filter.plist + `.fk.json` pair. P2-05 must implement a dedicated journaled transaction that updates both files together, verifies the old hashes immediately before commit, fsyncs the staged files and directory, and restores both originals on any pre-commit failure.
- The App-side IPC client/UI action is not connected in P2-04.
- The installed RootHide ElleKit version and exact filter semantics must still be checked on target devices. The strategy currently follows the project's pinned R16.1 research baseline; it is not proof of every installed ElleKit build.
- RootHide/Darwin ownership, mode, `openat`, `renameat`, `fsync`, and crash behavior remain device validation items.

## Validation performed

- `swiftc -frontend -parse` across all Swift files under Sources, HelperRuntime and Tests: passed.
- Focused Linux Swift typecheck of request models, RootHide filter strategy, package ownership resolver, ownership proof verifier and mutation authorizer: passed.
- Request-shape XCTest source added (four tests); XCTest not run in this environment.
- Xcode/iOS SDK build: not run (unavailable).
- No RootHide device test and no filesystem mutation performed.
