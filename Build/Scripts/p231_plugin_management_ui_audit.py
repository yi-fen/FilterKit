#!/usr/bin/env python3
from pathlib import Path
root = Path(__file__).resolve().parents[2]
ui = (root / 'Sources/Features/Plugins/PluginsView.swift').read_text()
app_ui = (root / 'Sources/Features/Apps/AppsView.swift').read_text()
checks = {
    'Plugins page has no first-time dylib import': 'isImportingPlugin' not in ui and 'plugins.import.button' not in ui,
    'Plugins page imports FilterKit backup data only': 'isImportingBackup' in ui and 'filterkitbackup' in ui and 'fileImporter(isPresented: $isImportingBackup' in ui,
    'Plugins page has no bulk activation or uninstall controls': 'plugins.selection.manage' not in ui and 'selectedPluginIDs' not in ui and 'plugins.uninstall.locked_message' not in ui,
    'Plugin inventory and detail remain available': 'ForEach(visiblePlugins)' in ui and 'PluginScanDetailView(plugin: plugin)' in ui,
    'Hard-bound and soft-associated App relations are surfaced': 'plugins.association_manager.hard_bound' in ui and 'softAssociations' in ui and 'plugins.association_manager.associated' in ui,
    'Activation responsibility is directed to App detail': 'plugins.association_manager.activation_from_app' in ui,
    'First-time dylib import entry exists in App detail': 'apps.detail.import_plugin' in app_ui and 'isImportingPlugin = true' in app_ui,
    'Association target excludes hard-bound App': 'apps.filter { $0.bundleIdentifier != hardBoundID }' in ui,
    'Association helper commit remains gated': 'pluginAssociationCommitReleased = false' in (root / 'Sources/Environment/Helper/HelperDeploymentCoordinator.swift').read_text() and 'pluginAssociationCommitReleased = false' in (root / 'Sources/Environment/Helper/Runtime/HelperRequestDispatcher.swift').read_text(),
}
for name, ok in checks.items(): print(('PASS' if ok else 'FAIL') + ' ' + name)
if not all(checks.values()): raise SystemExit(1)
print(f'{len(checks)}/{len(checks)} checks passed')
