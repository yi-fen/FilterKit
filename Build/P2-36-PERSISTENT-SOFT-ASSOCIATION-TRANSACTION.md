# P2-36 — Soft-association transaction policy

## Scope delivered in this source package

P2-36 adds a deterministic Helper-side policy contract for replacing a plugin's complete soft-association set. It formalizes the boundary between the Plugins page (relationship membership) and the App detail page (activation state).

The policy:
- validates bundle identifiers and rejects duplicates;
- rejects the hard-bound source App;
- caps the requested set at 512 entries;
- requires every newly added association to start disabled;
- preserves each existing association's activation bit;
- rejects removal of an enabled association until the App detail page has disabled it;
- returns a stable, sorted association list.

Unit tests cover these invariants. The host audit checks the policy, test coverage, page-boundary invariant, and release gates.

## Explicit release limitation

This package does **not** claim that persistent soft-association writes are released. Both `HelperDeploymentCoordinator.pluginAssociationCommitReleased` and `HelperRequestDispatcher.pluginAssociationCommitReleased` remain `false`. The existing single-target enable/disable IPC is not silently repurposed as a full-set transaction. The production Helper transaction path must be extended and validated before the gate can be opened.

No jailbreak files are modified by the host smoke test. No RootHide device IPC, root-owned filesystem transaction, crash recovery, code signing, or ElleKit injection is exercised.
