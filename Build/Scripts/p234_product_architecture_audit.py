#!/usr/bin/env python3
from pathlib import Path
import sys
root = Path(__file__).resolve().parents[2]
home = (root / 'Sources/Features/Home/HomeView.swift').read_text()
apps = (root / 'Sources/Features/Apps/AppsView.swift').read_text()
plugins = (root / 'Sources/Features/Plugins/PluginsView.swift').read_text()
settings = (root / 'Sources/Features/Settings/SettingsView.swift').read_text()
checks = []
def check(name, ok): checks.append((name, bool(ok)))
check('Home dashboard replaces placeholder', 'home.overview' in home and 'home.placeholder.title' not in home)
check('Home summarizes installed apps and discovered plugins', all(x in home for x in ['home.apps', 'home.plugins', 'installedAppCount', 'pluginCount']))
check('Home summarizes Filter health and associations', all(x in home for x in ['home.filter.parsed', 'home.filter.invalid', 'associatedAppCount']))
check('Home environment status is explicitly qualified', all(x in home for x in ['home.status.ellekit_detected', 'home.status.root_detected_ellekit_uncertain', 'home.status.environment_unresolved']))
check('First-time dylib/plist import exists on App detail', 'apps.detail.inject_plugin' in apps and 'fileImporter(isPresented: $isImportingPlugin' in apps)
check('App detail computes plugin relationships for selected Bundle ID', all(x in apps for x in ['hardBoundBundleIdentifier == app.bundleIdentifier', 'softAssociatedBundleIdentifiers.contains(app.bundleIdentifier)']))
check('Plugins page has no dylib/plist importer', 'isImportingPlugin' not in plugins and 'apps.detail.inject_plugin' not in plugins and 'plugins.import.button' not in plugins)
plugin_screen = plugins[plugins.index('struct PluginsView: View'):plugins.index('private struct BackupRestoreReview')]
check('Plugins page only imports FilterKit backup data', 'isImportingBackup' in plugin_screen and 'filterkitbackup' in plugin_screen and 'fileImporter(isPresented: $isImportingBackup' in plugin_screen and 'fileImporter(isPresented: $isImportingPlugin' not in plugin_screen and 'filenameExtension: \"dylib\"' not in plugin_screen)
check('Plugins page exposes no enable/disable mutation controls', 'PluginAssociationPreviewSection(plugin: plugin)' not in plugins and 'plugins.management.actions' not in plugins)
check('Plugin detail exposes immutable hard-bound identity and editable soft-association manager', all(x in plugins for x in ['PluginSoftAssociationManagerSection(plugin: plugin)', 'hardBoundID', 'softAssociations', 'plugins.association_manager.hard_bound']))
check('Settings no longer duplicates Home inventory statistics', 'settings.filter.inventory' not in settings)
for file, key in [
 ('Sources/Environment/Deployment/PluginToggleReleaseGate.swift','productionMutationReleased = false'),
 ('Sources/Environment/Helper/HelperDeploymentCoordinator.swift','executionReleased = false'),
 ('Sources/Environment/Helper/HelperDeploymentCoordinator.swift','pluginAssociationCommitReleased = false'),
 ('Sources/Environment/Helper/Runtime/HelperRequestDispatcher.swift','executionReleased = false'),
 ('Sources/Environment/Helper/Runtime/HelperRequestDispatcher.swift','pluginAssociationCommitReleased = false'),
 ('Sources/Environment/Helper/Execution/HelperProductionDeploymentBackend.swift','executionReleased = false')]:
 check(f'Production write gate remains closed: {Path(file).name}', key in (root/file).read_text())
for name, ok in checks: print(('PASS' if ok else 'FAIL') + ' ' + name)
failed=[name for name,ok in checks if not ok]
print(f'P2-34 product architecture audit: {len(checks)-len(failed)}/{len(checks)} passed')
if failed: sys.exit(1)
