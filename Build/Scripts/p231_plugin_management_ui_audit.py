#!/usr/bin/env python3
from pathlib import Path
root = Path(__file__).resolve().parents[2]
ui = (root / 'Sources/Features/Plugins/PluginsView.swift').read_text()
checks = {
    'visible plugin import action': 'plugins.import.button' in ui and 'isImportingPlugin = true' in ui,
    'managed selection mode': 'plugins.selection.manage' in ui and 'selectedPluginIDs' in ui,
    'hard-bound excluded from bulk selection': 'plugin.hardBoundBundleIdentifier == nil' in ui,
    'FilterKit ownership required': 'plugin.ownership == .filterKit' in ui,
    'permission required': 'plugin.managementPermission?.canModify == true' in ui,
    'paired plugin required': 'plugin.pairingState == .paired' in ui,
    'uninstall explicitly locked': 'plugins.uninstall.locked_message' in ui and '.disabled(true)' in ui,
    'association target excludes hard-bound app': 'apps.filter { $0.bundleIdentifier != plugin.hardBoundBundleIdentifier }' in ui,
    'association helper commit still gated': 'executionNotReleased' in ui,
}
for name, ok in checks.items(): print(('PASS' if ok else 'FAIL') + ' ' + name)
if not all(checks.values()): raise SystemExit(1)
print(f'{len(checks)}/{len(checks)} checks passed')
