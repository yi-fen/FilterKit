# P1-14 — Association Intent, Effective App Set, and Non-mutating Filter.plist Preview

## Scope

P1-14 turns the existing hard-bound/soft-association read model into a pure desired-state plan and produces a non-mutating preview of possible `Bundles` additions. It does not add persistence, Helper deployment, plist serialization, or filesystem writes.

## Association model

- `PluginAssociationPlan` keeps the immutable hard-bound source Bundle ID separate from soft associations.
- Each soft association has an explicit desired enabled bit.
- Existing schema 1/2 manifests do not carry a per-soft-App enabled bit. The compatibility bridge from `PluginAssociationSnapshot` interprets each recorded soft association as desired enabled; this is a compatibility interpretation, not a claim about current runtime injection.
- `PluginAssociationPlanResolver` computes effective Bundle IDs against the installed App inventory:
  - hard-bound source App is effective only while installed; its identity is never migrated;
  - enabled and installed soft associations are effective;
  - disabled soft associations remain in the desired plan but are excluded from the effective set;
  - missing soft Apps remain recorded and are reported separately;
  - malformed IDs, duplicate soft entries, and hard-bound-as-soft entries are reported.
- `PluginAssociationPlanEditor` only returns an updated in-memory value. It denies edits for non-manageable plugins, prevents hard-bound edits, and requires a soft App to be installed before adding/enabling it.
- No persistence format or write path is introduced in this phase.

## Filter.plist preview

- `FilterPlistAssociationPreview` parses the original plist using the existing read-only parser.
- It retains the exact original `Data` and SHA-256, reports the original `Bundles`, and proposes additions without removing or reordering original entries.
- Unknown plugin-owned keys remain in the original byte payload; the preview does not serialize a replacement plist.
- `removedBundles` is always empty.
- `canApply` is always false and profile verification remains required.
- Invalid original plist data is never repaired or overwritten automatically.

## ElleKit source semantics research

The public RootHide ElleKit repository overview describes ElleKit as an injector/hooking library and documents Substrate/libhooker APIs, but the browsable repository overview does not establish the exact `Filter.plist` matching semantics for `Bundles`, `Executables`, `Classes`, `Mode`, wildcard behavior, or merge behavior. The repository package index confirms ElleKit package versions and package identity, not plist rule semantics. Therefore this phase does not claim that the previewed Bundle set is a proven final injection rule, and does not enable any write operation.

References:
- `https://github.com/roothide/ellekit`
- `https://github.com/roothide/roothide.github.io/blob/main/Packages`
- RootHide developer path guidance: `https://github.com/RootHide/Developer/blob/main/roothide.md`

The project baseline remains the pinned ElleKit reference recorded in project docs. Exact source-commit inspection and RootHide/Rootless device validation are still required before applying a rule transformation. RootHide semantics must not be inferred for Rootless.

## Safety invariants

1. No target App Bundle modification or re-signing.
2. No dylib rename, `.disabled` marker, plist rewrite, or injection execution.
3. No dpkg database mutation or package-manager takeover.
4. Hard-bound identity is immutable.
5. Non-FilterKit and conflicted/unverified plugins remain non-manageable through existing P1-12 authorization.
6. Desired association state, installed-App availability, plist observation, and runtime load evidence remain separate.

## Files added

- `Sources/Core/Models/PluginAssociationPlan.swift`
- `Sources/Core/Models/FilterPlistAssociationPreview.swift`
- `Tests/UnitTests/PluginAssociationPlanTests.swift`
- `Tests/UnitTests/FilterPlistAssociationPreviewTests.swift`
- `Build/P1-14-ASSOCIATION-PLAN-AND-PLIST-PREVIEW.md`
- `Build/TEST-REPORT-P1-14.md`
