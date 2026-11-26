# P2-31 — Plugin Management UI Surface

## Delivered
- Added a dedicated, always-visible Import Plugin toolbar action on the Plugins tab.
- Added a multi-file picker for `.dylib` and `.plist` inputs and an explicit import-preflight review.
- Added Manage mode with per-plugin checkboxes and a selected-count/action bar.
- Bulk selection is restricted to paired, FilterKit-owned plugins with `canModify == true` and no hard-bound App.
- Plugin detail exposes App association controls. Candidate target Apps continue to exclude the plugin's hard-bound Bundle ID.
- Added an explicit uninstall affordance, but it remains disabled until the uninstall Helper transaction is device-validated and released.
- Added Chinese and English strings and a static UI policy audit.

## Safety boundary
This stage does not install imported files, copy data into the jailbreak plugin directory, delete plugins, or commit ElleKit filter changes. The import picker currently provides file selection and a clearly labelled preflight only. Association commit remains subject to the existing Helper execution release gate. Third-party/package-manager plugins remain read-only.

## Validation
- Swift frontend parse: `Sources/Features/Plugins/PluginsView.swift` passed.
- `Build/scripts/p231_plugin_management_ui_audit.py`: 9/9 passed.
- Basic `.strings` syntax checks for `zh-Hans` and `en`: passed.
- Full Xcode/iOS SDK build and on-device UI validation were not available in this environment.
