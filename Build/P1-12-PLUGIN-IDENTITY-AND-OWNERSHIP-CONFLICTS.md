# P1-12 — Plugin Identity Reconciliation and Ownership Conflict Detection

## Scope

P1-12 builds on the read-only P1-11 inventory. It adds cross-entry identity comparison, stronger manifest-to-binary binding, explicit package-owner conflict states, and authorization downgrades when evidence conflicts. It does not deploy, enable, disable, uninstall, or load plugins.

## Binary identity fingerprint

`PluginIdentityAnalyzer` builds a deterministic SHA-256 fingerprint from normalized, sorted values:

- Mach-O install name(s)
- UUID(s) across all architecture slices
- CDHash value(s)
- architecture label(s)

Case and ordering differences do not change the fingerprint. A fingerprint is only produced when at least one UUID or CDHash is available. Missing identity metadata remains `insufficientFingerprint`; FilterKit does not invent an identity from a filename.

## Conflict classes

- `duplicateIdentity`: multiple inventory entries share the same full identity fingerprint.
- `installNameCollision`: the same install name is associated with different binary fingerprints; possible fork/rebuild.
- `uuidCDHashMismatch`: the same Mach-O UUID appears with different CDHashes.
- `unresolvedBasenameCollision`: case-insensitive basename collisions prevent a safe one-to-one file pairing.
- `insufficientFingerprint`: neither UUID nor CDHash is available; this is not itself a conflict.

The scanner no longer picks the lexicographically first file from a case-insensitive duplicate group. It marks the group invalid and leaves its file identity unresolved.

## Manifest binding

`FilterKitPluginManifest` now recognizes schema version 1 and 2:

- Schema 1 remains backward compatible and binds the manifest to exact dylib/plist names and full-file SHA-256 hashes. It is reported as `fileHashesOnly`.
- Schema 2 additionally requires `machOIdentitySHA256`, calculated with the same canonical install-name/UUID/CDHash/architecture fingerprint function. A missing or mismatched binary fingerprint makes the manifest unverified.
- Schema 2 is reported as `binaryIdentityVerified` only after the binary fingerprint matches.

A valid manifest is still not sufficient to override package-manager ownership evidence.

## Package ownership conflict handling

The scanner independently queries dpkg file ownership for the dylib and plist:

- If both are owned by the same package, package-manager ownership is recorded.
- If only one is owned by a package, that exact file-ownership evidence is retained.
- If the dylib and plist belong to different packages, ownership becomes `unknown` with `multiplePackageOwners`.
- If a verified FilterKit manifest conflicts with any package-manager ownership evidence, ownership becomes `unknown` with `filterKitVsPackageManager`.

The scan item retains separate dylib and plist package-owner identifiers for diagnosis. No dpkg command is invoked and no package database is modified.

## Authorization behavior

Identity or ownership conflicts force a read-only permission result:

- duplicate identity, install-name collision, UUID/CDHash mismatch, or unresolved basename collision → `readOnlyIdentityConflict`
- any ownership conflict → `readOnlyOwnershipConflict`

Ownership conflict takes priority. The Plugins page's “manageable” filter continues to rely on `managementPermission.canModify`, so conflicted entries cannot appear as manageable even if their manifest otherwise verifies.

`insufficientFingerprint` alone does not automatically revoke management when the existing P1-10 manifest/file-hash checks pass; the UI explicitly reports that no stronger binary fingerprint was available.

## Scope limitation: directory reconciliation

P1-04 intentionally permits scanning only one uniquely resolved plugin directory. P1-12 compares all entries returned by that selected directory. It does not bypass the ambiguous-directory fail-closed rule to scan several competing roots. Cross-root reconciliation requires a future Profile-level design that explicitly authorizes multiple roots and records each root's provenance.

## Safety

- Read-only file and dpkg metadata access.
- No writes, renames, chmod, deletion, `dlopen`, or code execution.
- No target App Bundle modification or re-signing.
- No inference that a disk-resident plugin is loaded.
- UUID/CDHash/fingerprint comparison does not establish signature trust or loaded state.
