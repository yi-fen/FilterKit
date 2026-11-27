# P2-36 Changelog

- Added `HelperPluginAssociationMutationPolicy` for full-set soft-association invariants.
- Added unit tests for disabled-by-default additions, activation-bit preservation, enabled-removal denial, hard-bound immutability, duplicates, and deterministic ordering.
- Added P2-36 host audit and smoke runner.
- Kept production association commit release gates closed; no unverified filesystem mutation path was enabled.
