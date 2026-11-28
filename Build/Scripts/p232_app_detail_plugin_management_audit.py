#!/usr/bin/env python3
from pathlib import Path
root = Path(__file__).resolve().parents[2]
apps = (root / 'Sources/Features/Apps/AppsView.swift').read_text()
plugins = (root / 'Sources/Features/Plugins/PluginsView.swift').read_text()
zh = (root / 'Resources/zh-Hans.lproj/Localizable.strings').read_text()
en = (root / 'Resources/en.lproj/Localizable.strings').read_text()
checks = {
    'App list opens functional plugin detail': 'AppDetailView(app: app)' in apps and 'AppDetailPluginManagementSection(app: app)' in apps,
    'App detail has prominent Inject Plugin action': 'apps.detail.inject_plugin' in apps and 'isImportingPlugin = true' in apps,
    'App detail accepts dylib and plist': 'filenameExtension: "dylib"' in apps and 'filenameExtension: "plist"' in apps,
    'App detail shows manageable plugin count': 'apps.detail.manageable_plugins' in apps and 'manageableCount' in apps,
    'App detail lists plugins associated by hard or soft binding': 'plugin.hardBoundBundleIdentifier == app.bundleIdentifier' in apps and 'plugin.softAssociatedBundleIdentifiers.contains(app.bundleIdentifier)' in apps,
    'App detail matches plugin Filter bundle configuration': 'plugin.filterConfiguration?.bundles' in apps,
    'Per-App activation state is resolved through the shared activation resolver': 'AppPluginActivationStateResolver().resolve(' in apps,
    'Activation controls are disabled when policy disallows preview/toggle': '!activation.canPreviewToggle' in apps,
    'Injection is explicitly preflight only': 'does not copy files or modify ElleKit configuration' in en and '不会复制文件或修改 ElleKit 配置' in zh,
    'Real mutations remain safety-gated': 'apps.detail.plugin_mutations_locked' in apps,
    'Chinese localization complete': all(f'"{k}"' in zh for k in ['apps.detail.inject_plugin','apps.detail.manageable_plugins','apps.detail.no_related_plugins','apps.detail.plugin_manageable','apps.detail.plugin_read_only']),
    'English localization complete': all(f'"{k}"' in en for k in ['apps.detail.inject_plugin','apps.detail.manageable_plugins','apps.detail.no_related_plugins','apps.detail.plugin_manageable','apps.detail.plugin_read_only']),
    'Plugin library remains present with backup-only import and soft-association manager': 'struct PluginsView: View' in plugins and 'filterkitbackup' in plugins and 'PluginSoftAssociationManagerSection(plugin: plugin)' in plugins and 'plugins.import.button' not in plugins and 'plugins.selection.manage' not in plugins,
}
for name, ok in checks.items(): print(('PASS' if ok else 'FAIL') + ' ' + name)
if not all(checks.values()): raise SystemExit(1)
print(f'{len(checks)}/{len(checks)} checks passed')
