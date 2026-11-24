# P1-10 — Plugin Filter Parsing and Management Authorization

## Scope

P1-10 adds read-only parsing of paired plugin plist files and a centralized authorization decision for future management operations. It does not enable, disable, rewrite, deploy, or uninstall plugins.

## Filter parsing

`PluginFilterConfiguration.parse(_:)` uses Foundation `PropertyListSerialization`, which accepts XML and binary property lists and supports legacy plist encodings accepted by the platform.

- Reads a nested `Filter` dictionary when present.
- Otherwise treats the top-level dictionary as the filter dictionary.
- Extracts string members from `Bundles`, `Executables`, and `Classes`.
- Preserves `Mode` as a display representation; P1-10 deliberately does not infer Any/All semantics.
- Lists unknown field names without rewriting or discarding their values.
- Distinguishes valid, partial, invalid, and unavailable parse states.
- Does not serialize or write the parsed dictionary back. Original plist bytes and SHA-256 remain the scanner's source of truth.

## Management authorization

`PluginManagementPermission.evaluate` is the single read-only policy decision used by the Plugins list scope and detail view.

A plugin is eligible for future FilterKit management only when all are true:

1. ownership is `filterKit` (verified manifest and file hashes from P1-09);
2. dylib/plist pairing is `paired`;
3. dylib is recognized as Mach-O;
4. parsed Filter configuration is fully `valid`;
5. FilterKit plugin identity is a valid UUID.

`packageManager` and `unknown` are always read-only. Invalid pairing/configuration and unverified identity are also read-only. UI visibility is not itself authorization.

## Plugins UI

- “Managed” scope now includes only items whose centralized permission decision says `canModify`.
- “All” scope continues to show FilterKit, package-manager, and unknown-source items.
- Detail view displays the permission reason and read-only Filter fields: container, parse state, Bundles, Executables, Classes, Mode, and unknown key names.
- Hard-bound and soft-associated App identities remain visible only for verified FilterKit-owned items.

## Validation

- Swift source parse: passed.
- Foundation model/scanner typecheck on Linux Swift: passed with minimal app protocol stub.
- P1-10 executable smoke test: passed (nested Filter dictionary, top-level dictionary, XML/binary plist, unknown key preservation, and permission isolation).
- Localization parity: 164 keys in each language.
- Architecture guard: passed.
- Xcode/iOS SDK build and XCTest execution: not run in this environment.
- Dopamine RootHide/Rootless device validation: not run.

## Safety boundary

No file writes, renames, chmod, deletes, dpkg commands, target-App modifications, or injection operations were performed. `Mode` semantics and actual target ElleKit matching behavior remain subject to source/device verification.
