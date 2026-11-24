# P1-04 — DynamicLibraries / TweakInject directory location

## Scope

P1-04 is a read-only filesystem inspection phase. It does not create, write, rename, delete, chmod, chown, mount, or modify any jailbreak file. It does not invoke shell commands or load ElleKit.

## Directory roles

The locator deliberately distinguishes these paths relative to the validated JBROOT:

| Relative path | Classification | Can be selected as third-party plugin directory? |
|---|---|---:|
| `usr/lib/TweakInject` | TweakInject candidate | Yes, if it exists, is a directory, is readable and enumerable |
| `Library/MobileSubstrate/DynamicLibraries` | Legacy MobileSubstrate candidate | Yes, under the same checks |
| `Library/TweakInject` | ElleKit component directory candidate | No; evidence only |

`Library/TweakInject` is not treated as a plugin destination merely because ElleKit binaries may be installed there. The third-party plugin directory and ElleKit's own component layout remain separate concepts.

## Resolution rules

1. Inspect candidates relative to the already validated JBROOT; do not independently guess a root.
2. Record existence, directory type, readability, enumerability, writability (observation only), symlink/canonical path, and immediate `.dylib` / `.plist` counts.
3. Canonicalize paths and merge aliases that resolve to the same physical path.
4. Select a directory only when exactly one distinct usable third-party candidate remains.
5. If both supported third-party layouts exist at distinct canonical paths, return `ambiguous`; never select the first or prefer one based on its name.
6. If only the ElleKit component directory exists, return `unavailable` for the plugin directory.
7. If a third-party candidate exists but cannot be read or enumerated, return `inaccessible` unless another independent usable candidate creates ambiguity.
8. An empty but readable/enumerable candidate directory is structurally usable; its zero file counts are reported and do not imply that plugins are installed.

## Environment handling

RootHide and Rootless use the same relative candidate layouts under their separately validated JBROOT. The report retains the environment kind. This phase does not claim that the layouts are identical across all jailbreak releases; actual device verification remains required.

## Integration

`ReadOnlyEnvironmentProvider.makeDiagnosticReport()` now delegates plugin directory inspection to `PluginDirectoryLocator`. `resolvedDynamicLibrariesPath` is populated only for a unique resolution. `resolvePaths()` therefore fails closed on ambiguity or unavailable paths.

The legacy field name `dynamicLibrariesCandidates` is retained for compatibility, but its contents now describe third-party plugin directory candidates. The richer `pluginDirectoryAssessment` contains role and evidence details.

## Explicit non-goals

- No decision yet about `.disabled` marker versus plist-based disablement.
- No deployment or write permission authorization.
- No plugin import, scanning ownership classification, or plist parsing in this phase.
- No assumption that a directory being writable means FilterKit is authorized to write there.
- No assertion that deployed files are loaded into any target process.

## Offline validation

The isolated smoke harness covers: unique TweakInject resolution, two distinct plugin directories causing ambiguity, and ElleKit component directory being excluded as a plugin destination. The full iOS/Xcode build and RootHide/Rootless jailbreak-device validation have not been performed in this environment.
