# P2-42-R9 Changelog

## Plugin list status
- Added separate list-row fields for plugin presence, configured load target, persisted App associations, per-App injection state, and source.
- App names resolve through the existing App display index; unmatched associations retain their Bundle IDs.
- Per-App injection is shown as enabled/disabled only when a valid, unambiguous Filter.plist agrees with the persisted association state. Global, Classes/Executables-ambiguous, partial, duplicate-key, or mismatched configurations remain unknown.

## Top-right scope toggle
- Kept the existing top-right toolbar filter button (not a Menu).
- Toggle switches between all paired plugins and FilterKit-owned plugins that have at least one persisted App association with an observed, enabled injection state.
- Ownership, association, and injection are all required; third-party, unassociated, disabled-only, or unverifiable plugins are excluded from the narrow scope.

## Safety
- Display-only projection. No Filter.plist, Manifest, association, or activation writes were added.
- No scanner, cache, polling loop, or production release gate changes.
