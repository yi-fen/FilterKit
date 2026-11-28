# P2-42 Changelog — Plugin Lifecycle & Helper Execution Boundary

## Implemented

- Centralized lifecycle authorization and page responsibility policy in `PluginLifecyclePolicy`.
- APP-only actions: first-time inject, enable, disable.
- Plugin-only actions: add/remove Additional App Association, export, restore, uninstall.
- Fixed Owner cannot be removed; Additional App Association removal requires the target App activation to be disabled first.
- Uninstall/export/restore require positive FilterKit ownership, a verified payload pair, and a verified manifest. Uninstall additionally requires every App activation to be disabled.
- App install availability is derived independently from the immutable binding topology. App uninstall/reinstall does not delete or rewrite Fixed Owner/Additional App Association records.
- Helper's final package-manager ownership recheck now preserves the explicit `packageOwned` denial rather than converting it into generic ownership-unavailable.
- Added a Helper-side final SHA-256 scan of dpkg-owned dylibs listed for the configured injection directory. Exact package-managed content duplicates are rejected at authorization and rechecked immediately before transaction execution; this complements the App-side preview and closes the previous preview-only gap for dpkg-managed files in that directory. A compiled host smoke test verified exact-match detection and non-match behavior.
- First-install target/manifest absence is rechecked before entering the atomic transaction; the transaction independently verifies absent dylib/plist/manifest under its process lock.

## Not implemented / deliberately gated

- No production injection, activation, uninstall, or restore writes were enabled.
- No new Helper uninstall IPC command or deletion transaction was introduced; uninstall requires a separately reviewed atomic transaction that removes the dylib, Filter.plist, and manifest as one recoverable unit.
- No APP/Plugin SwiftUI navigation redesign in this increment; the new policy is the shared domain contract for that follow-up.
- No RootHide/ElleKit device acceptance or Xcode build was possible in this Linux environment.

## P2-42-R2 — APP / Plugin page responsibility and terminology

- Renamed the APP detail's first-time action and accessibility identifier from Import Plugin to Inject Plugin (`apps.detail.inject_plugin` / `Inject Plugin`).
- Updated the APP-side ZIP/DEB/dylib preflight copy to describe injection, not generic import. The action remains read-only preflight and performs no file copy, Filter/Manifest write, or Helper mutation.
- Added a Plugin-detail-only uninstall affordance for positively FilterKit-owned plugins. It is intentionally disabled and explains that uninstall requires all per-App activations to be turned off in APP and awaits the Helper uninstall transaction/device acceptance.
- External/non-FilterKit plugins show read-only ownership messaging rather than an uninstall action.
- Kept Plugin page free of enable/disable toggles and first-time dylib/plist import. Association editing remains in Plugin; activation remains in APP.
- Updated page-boundary audit scripts and localization keys. Chinese and English key sets remain identical with no duplicate keys.
- All production mutation gates remain closed. No real injection, activation, association commit, restore, or uninstall was performed.
