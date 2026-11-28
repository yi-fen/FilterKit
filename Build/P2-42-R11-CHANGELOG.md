# P2-42-R11 — Plugin list/detail consistency

Baseline: `FilterKit-P2-42-R10-Source.zip`.

## Changes

- Kept the compact plugin-list presentation introduced in R10; no unbounded App-name expansion was added to list rows.
- Added an App association and injection section to plugin detail, using the same `PluginListStatus` projection as the list row.
- Detail shows the Fixed Owner first, then Additional App Associations, with per-App enabled/disabled/unknown status and App display-name fallback to Bundle ID.
- Detail now presents the same ownership source wording as the list (`FilterKit`, package manager, or unknown).
- Normalized additional association IDs by trimming whitespace and deduplicating case-insensitively. The Fixed Owner is not repeated as an additional association; original spelling is retained for display.
- Ambiguous duplicate association-state records remain `unknown`; no state is guessed.
- Kept global wildcard and non-Bundle-specific Filter.plist selector configurations from being projected as a per-App injection state.
- Added English and Simplified Chinese labels for the detail association section.
- No new scanner, polling loop, persistence path, or production mutation capability was introduced.

## Safety

This is a read-only presentation/model refinement. Existing injection, association mutation, uninstall, and backup-restore production gates remain unchanged and closed.
