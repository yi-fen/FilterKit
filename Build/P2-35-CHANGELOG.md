# P2-35 Changelog

- Added a shared `PluginScanRegistry` singleton holding the most recent plugin snapshot and reusing one in-flight background scan; the Plugins screen reads this snapshot instead of constructing its own scanner per appearance.
- Moved plugin environment probing and directory enumeration off the main actor into a detached utility task; the first foreground frame no longer runs a synchronous environment report.
- Warmed both inventories at launch from the root tab: App inventory and plugin registry prewarm in the background.
- Downgraded the first-scan full-screen loading state to a List-first inline progress row in both the Apps and Plugins screens; error, unavailable-directory, empty, and failure terminal states are preserved.
- Kept all existing loading flags and state branches. No loading UI code was removed; only the scan timing, snapshot ownership, and shell placement changed.
- App inventory prewarm, snapshot read, and in-flight reuse retained from the prior pass.
- Version unchanged (1.0.0). No dylib binary inspection, package-ownership query, hash verification, file write, resigning, or target-app Bundle modification was added.
