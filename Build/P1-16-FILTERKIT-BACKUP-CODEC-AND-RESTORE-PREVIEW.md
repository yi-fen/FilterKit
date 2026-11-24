# P1-16 — FilterKitBackup codec and restore preview

## Scope
P1-16 implements the portable backup data layer and a non-mutating restore preview. It does not write plugin files, invoke a Helper, change Filter.plist, or restore into a live jailbreak directory.

## Format
- Format identifier: `FilterKitBackup`.
- Current schema: 2; schema 1 remains readable under the established compatibility rule (legacy soft associations default to enabled).
- Each entry carries complete Base64-encoded dylib and plist bytes, SHA-256 digests, plugin UUID, hard-bound Bundle ID, and soft-association states.
- Optional manifest payload is accepted only when both its Base64 data and SHA-256 are present and valid. Optional Mach-O identity digest is retained as provenance; this portable layer does not claim to validate the digest against a real Mach-O parser.
- JSON output uses ISO-8601 dates and sorted keys.

## Validation
- Rejects unsupported schema, wrong format, empty archives, duplicate plugin IDs, unsafe leaf names, wrong file extensions, empty/invalid Base64, malformed hashes, SHA-256 mismatch, partial manifest payload, invalid or duplicate associations, and hard-bound/soft-association overlap.
- Schema 2 requires explicit soft-association states and requires the state list to match the legacy Bundle-ID index exactly.
- Schema 1 preserves legacy semantics by treating listed soft associations as enabled.

## Restore preview
The preview classifies each entry as ready, hard-bound App missing, soft Apps missing, file conflict, or identity conflict. Missing soft Apps are reported but do not discard the saved association state. A missing hard-bound App blocks readiness and the original hard-bound identity is retained. Existing target files and known plugin identity conflicts block restore pending an explicit future conflict-resolution flow.

## Safety boundary
This phase only encodes, decodes, validates, and previews data. No file-system deployment or overwrite implementation is included. A valid backup is not proof that a target device supports the plugin or injection rules. App existence is supplied by the caller; the codec does not query LaunchServices itself.
