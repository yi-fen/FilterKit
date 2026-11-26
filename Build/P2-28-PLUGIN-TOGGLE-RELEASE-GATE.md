# P2-28 — Plugin Toggle Release Gate

## Goal

P2-28 is the first controlled rollout step toward real per-App plugin enable/disable and ElleKit injection. It adds an explicit release-readiness policy instead of treating a UI toggle, a successful plist edit, or a Helper response as proof that injection is safe or active.

## Release conditions

A mutation candidate must satisfy all of the following independently:

1. The RootHide/ElleKit enable and disable profile is source-verified and validated on a real device, including preservation of original filter-plist semantics.
2. The App↔Helper identity and peer credentials have been validated on that device.
3. Helper recovery journals are clean.
4. The durable audit sink is writable before a transaction.
5. The plugin is FilterKit-owned and its dylib/plist/manifest pair is verified.
6. The target App is installed and available.
7. The immutable hard-bound source App is never treated as a toggleable soft association.
8. The user explicitly confirms the operation.
9. The independent production release switch is open.

The policy reports blockers individually. Passing the evidence checks is not itself an authorization to write.

## P2-28 release state

`PluginToggleReleaseGate.productionMutationReleased` remains `false`. The existing independent Helper gates also remain `false`:

- `HelperRequestDispatcher.executionReleased`
- `HelperRequestDispatcher.pluginAssociationCommitReleased`
- `HelperDeploymentCoordinator.executionReleased`
- `HelperDeploymentCoordinator.pluginAssociationCommitReleased`
- `HelperProductionDeploymentBackend.executionReleased`

No real plugin file installation, filter-plist mutation, enable/disable operation, injection, uninstall, or recovery write is released by this phase.

## Why the switch is not opened yet

The available build host is Linux and there is no verified RootHide device session or signed production App/Helper pair in this phase. The current source-reference profile is not device validation. Opening a write gate without confirming the exact ElleKit filter semantics, App/Helper peer identity, recovery behavior, and runtime load observations could leave an App with a broken filter configuration or claim injection success when no process loaded the dylib.

## Validation

Run:

```sh
Build/Host/run-p228-toggle-release-smoke.sh
```

The smoke validates both the all-positive-but-release-closed case and each safety blocker. It is a host policy test, not a RootHide runtime test.

## Next release step

P2-29 should gather signed App/Helper artifacts and real RootHide device evidence: confirm the exact ElleKit profile and filter plist semantics, exercise a single test plugin against a disposable target App, verify enable→launch→observed load→disable→relaunch→not loaded, and capture rollback/recovery/audit results. Only after that evidence is reviewed should a narrowly scoped association-commit release be considered. Full dylib deployment and uninstall remain separate later gates.
