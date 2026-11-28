# P2-42-R6 — Plugin app-name enrichment and runtime visibility

## Changes

- Reworked Plugin-page app-name enrichment around `PluginAppDisplayIndex`.
  - Bundle ID keys are normalized to lowercase for stable matching.
  - Executable-name keys are normalized and empty executable names are ignored.
  - Empty display names fall back to the Bundle ID.
  - Unmatched associations continue to display the Bundle ID rather than disappearing.
  - Association names remain presentation-only; they do not alter plugin ownership or binding topology.
- Corrected unknown-source presentation. An unknown-owned item now displays `来源：未知` / `Source: unknown`, including entries that happen to contain an unverified manifest file. A manifest file alone is not ownership proof.
- Added a read-only host-process probe using `proc_listpids` / `proc_pidpath`, with exact executable-path matching against installed app bundle metadata.
- Added a five-second refresh of process evidence while the Plugin page task is active. This refresh does not invoke PluginScanRegistry or rescan plugin directories.
- Added explicit runtime wording that distinguishes host-app process visibility from proof that the plugin dylib has loaded.
- Added `PluginAppDisplayIndexTests` for case normalization, identity fallback, and deterministic name deduplication.
- Repaired a pre-existing malformed Chinese localization entry (`settings.backup.only_installed_apps.note`) discovered during localization validation.

## Runtime evidence boundary

This phase detects whether a target app process can be observed. It does **not** prove that a particular ElleKit dylib is present in that process's loaded-image list. Therefore the UI says `目标 App 运行中 · 插件是否已加载尚未确认` when a matching host process is seen, and does not label that state as “plugin running”. A definitive plugin-loaded state requires trusted jailbreak-aware cross-process image inspection/attestation through a separately validated Helper capability. No such capability is introduced or assumed in R6.

All runtime probing is read-only. No process is signalled, attached to, suspended, or modified.

## Safety invariants

- APP remains the only first-injection entry point.
- Plugin management/ownership rules are unchanged.
- No plugin file, plist, Manifest, injection rule, or Helper authorization is modified by the runtime probe.
- Production injection, toggle, restore-write, association-commit, and uninstall release gates remain closed.
