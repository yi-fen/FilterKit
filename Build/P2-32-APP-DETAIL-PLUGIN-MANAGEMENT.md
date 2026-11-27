# P2-32 — App Detail Plugin Management Entry

## Purpose

P2-31 added plugin import and selection entry points to the global Plugins tab, but the Apps tab still navigated to an informational placeholder. P2-32 replaces that placeholder with an app-scoped plugin management surface.

## UI changes

- The Apps list now opens `AppDetailView` rather than an informational-only placeholder.
- The App detail contains a visible **Import Plugin for This App** button; it is not hidden in a toolbar menu.
- The file picker accepts `.dylib` and `.plist` files and allows multiple selection.
- After selection, the UI displays a read-only import preflight review naming the selected files.
- The detail shows a count of manageable plugins and lists plugins associated with this App through hard binding, soft association, filter bundle rules, or executable rules.
- Plugin rows open an app-scoped detail page showing ownership, pairing, target App, and file names.
- Hard-bound plugins, third-party plugins, unpaired plugins, and plugins without modification permission are displayed as read-only and are not counted as manageable.
- A refresh action reuses the shared `PluginScanRegistry` inventory.

## Safety boundary

This stage fixes the missing UI entry point. Import remains file selection plus review only: it does not copy a dylib/plist into jailbreak directories, create ownership manifests, or edit ElleKit rules. Association commit, enable/disable, and uninstall remain locked. The UI explicitly says so; no production mutation flag is enabled.

## Validation

- `swiftc -frontend -parse Sources/Features/Apps/AppsView.swift Sources/Features/Plugins/PluginsView.swift` — passed.
- `Build/scripts/p232_app_detail_plugin_management_audit.py` — 13/13 passed.
- `Build/scripts/p231_plugin_management_ui_audit.py` — 9/9 passed.
- Full Xcode/iOS SDK build and on-device UI acceptance were not available in this environment and are not claimed.
